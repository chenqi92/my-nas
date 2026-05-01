import 'dart:async';

import 'package:flutter/services.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 原生 AVPlayer 事件类型
enum NativeAVPlayerEventType {
  initialized,
  ready,
  playingChanged,
  bufferingChanged,
  positionChanged,
  durationChanged,
  videoSizeChanged,
  audioTrackChanged,
  subtitleTrackChanged,
  seekCompleted,
  completed,
  error,
  pipWillStart,
  pipDidStart,
  pipWillStop,
  pipDidStop,
  pipError,
  pipPossibleChanged,
}

/// 原生 AVPlayer 事件
class NativeAVPlayerEvent {
  const NativeAVPlayerEvent({
    required this.playerId,
    required this.type,
    this.data = const {},
  });

  final int playerId;
  final NativeAVPlayerEventType type;
  final Map<String, dynamic> data;

  factory NativeAVPlayerEvent.fromMap(Map<dynamic, dynamic> map) {
    final eventName = map['event'] as String?;
    final type = NativeAVPlayerEventType.values.firstWhere(
      (e) => e.name == eventName,
      orElse: () => NativeAVPlayerEventType.error,
    );

    return NativeAVPlayerEvent(
      playerId: (map['playerId'] as num?)?.toInt() ?? 0,
      type: type,
      data: Map<String, dynamic>.from(map)..remove('playerId')..remove('event'),
    );
  }
}

/// 原生 AVPlayer 平台通道
///
/// 与 iOS/macOS 原生 AVPlayer 通信
class NativeAVPlayerChannel {
  NativeAVPlayerChannel._();

  static NativeAVPlayerChannel? _instance;
  static NativeAVPlayerChannel get instance =>
      _instance ??= NativeAVPlayerChannel._();

  static const _methodChannel =
      MethodChannel('com.kkape.mynas/native_av_player');
  static const _eventChannel =
      EventChannel('com.kkape.mynas/native_av_player/events');

  StreamSubscription<dynamic>? _eventSubscription;
  final _eventController = StreamController<NativeAVPlayerEvent>.broadcast();

  /// 事件流
  Stream<NativeAVPlayerEvent> get eventStream => _eventController.stream;

  /// 初始化事件监听
  void initialize() {
    _eventSubscription?.cancel();
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          final playerEvent = NativeAVPlayerEvent.fromMap(event);
          _eventController.add(playerEvent);
        }
      },
      onError: (Object error) {
        logger.e('NativeAVPlayerChannel: Event stream error', error);
      },
    );
  }

  /// 销毁
  void dispose() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  /// 创建播放器实例
  Future<int> create() async {
    final playerId = await _methodChannel.invokeMethod<int>('create');
    return playerId ?? 0;
  }

  /// 打开视频
  Future<void> open(int playerId, String url, {Map<String, String>? headers}) async {
    await _methodChannel.invokeMethod<void>('open', {
      'playerId': playerId,
      'url': url,
      'headers': headers,
    });
  }

  /// 播放
  Future<void> play(int playerId) async {
    await _methodChannel.invokeMethod<void>('play', {'playerId': playerId});
  }

  /// 暂停
  Future<void> pause(int playerId) async {
    await _methodChannel.invokeMethod<void>('pause', {'playerId': playerId});
  }

  /// 跳转（毫秒）
  Future<void> seek(int playerId, int positionMs) async {
    await _methodChannel.invokeMethod<void>('seek', {
      'playerId': playerId,
      'position': positionMs,
    });
  }

  /// 设置播放速度
  Future<void> setSpeed(int playerId, double speed) async {
    await _methodChannel.invokeMethod<void>('setSpeed', {
      'playerId': playerId,
      'speed': speed,
    });
  }

  /// 设置音量 (0.0-1.0)
  Future<void> setVolume(int playerId, double volume) async {
    await _methodChannel.invokeMethod<void>('setVolume', {
      'playerId': playerId,
      'volume': volume,
    });
  }

  /// 获取音轨列表
  Future<List<Map<String, dynamic>>> getAudioTracks(int playerId) async {
    final result = await _methodChannel.invokeMethod<List<dynamic>>('getAudioTracks', {
      'playerId': playerId,
    });
    return result?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
  }

  /// 设置音轨
  Future<void> setAudioTrack(int playerId, int index) async {
    await _methodChannel.invokeMethod<void>('setAudioTrack', {
      'playerId': playerId,
      'index': index,
    });
  }

  /// 获取字幕轨道列表
  Future<List<Map<String, dynamic>>> getSubtitleTracks(int playerId) async {
    final result = await _methodChannel.invokeMethod<List<dynamic>>('getSubtitleTracks', {
      'playerId': playerId,
    });
    return result?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
  }

  /// 设置字幕轨道
  Future<void> setSubtitleTrack(int playerId, int index) async {
    await _methodChannel.invokeMethod<void>('setSubtitleTrack', {
      'playerId': playerId,
      'index': index,
    });
  }

  /// 禁用字幕
  Future<void> disableSubtitle(int playerId) async {
    await _methodChannel.invokeMethod<void>('disableSubtitle', {
      'playerId': playerId,
    });
  }

  /// 获取当前状态
  Future<Map<String, dynamic>> getState(int playerId) async {
    final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>('getState', {
      'playerId': playerId,
    });
    return result != null ? Map<String, dynamic>.from(result) : {};
  }

  /// 截图
  Future<List<int>?> screenshot(int playerId) async {
    final result = await _methodChannel.invokeMethod<Uint8List>('screenshot', {
      'playerId': playerId,
    });
    return result?.toList();
  }

  /// 进入画中画
  Future<bool> enterPiP(int playerId) async {
    final result = await _methodChannel.invokeMethod<bool>('enterPiP', {
      'playerId': playerId,
    });
    return result ?? false;
  }

  /// 退出画中画
  Future<bool> exitPiP(int playerId) async {
    final result = await _methodChannel.invokeMethod<bool>('exitPiP', {
      'playerId': playerId,
    });
    return result ?? false;
  }

  /// 销毁播放器
  Future<void> disposePlayer(int playerId) async {
    await _methodChannel.invokeMethod<void>('dispose', {
      'playerId': playerId,
    });
  }
}
