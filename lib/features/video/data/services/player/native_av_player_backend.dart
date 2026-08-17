import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/player/native_av_player_channel.dart';
import 'package:my_nas/features/video/data/services/player/video_player_backend.dart';
import 'package:my_nas/features/video/presentation/widgets/native_av_player_view.dart';

/// 原生 AVPlayer 播放器后端实现
///
/// 使用 iOS/macOS 原生 AVPlayer 播放视频，支持 Dolby Vision
class NativeAVPlayerBackend implements VideoPlayerBackend {
  NativeAVPlayerBackend() {
    _initFuture = _init();
  }

  final NativeAVPlayerChannel _channel = NativeAVPlayerChannel.instance;
  late final Future<void> _initFuture;
  int _playerId = 0;

  bool _isInitialized = false;
  bool _isDisposed = false;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isPiPActive = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1.0;
  double _speed = 1.0;
  int? _videoWidth;
  int? _videoHeight;
  int _currentAudioTrackIndex = -1;
  int _currentSubtitleTrackIndex = -1;

  StreamSubscription<NativeAVPlayerEvent>? _eventSubscription;

  // Stream controllers
  final _playingController = StreamController<bool>.broadcast();
  final _bufferingController = StreamController<bool>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _volumeController = StreamController<double>.broadcast();
  final _speedController = StreamController<double>.broadcast();
  final _errorController = StreamController<String?>.broadcast();
  final _completedController = StreamController<bool>.broadcast();
  final _audioTracksController =
      StreamController<List<AudioTrackInfo>>.broadcast();
  final _subtitleTracksController =
      StreamController<List<SubtitleTrackInfo>>.broadcast();

  Future<void> _init() async {
    // 确保只在 Apple 平台上使用
    if (!Platform.isIOS && !Platform.isMacOS) {
      throw UnsupportedError(
        'NativeAVPlayerBackend is only supported on iOS and macOS',
      );
    }

    if (_isDisposed) return;

    _channel.initialize();
    final playerId = await _channel.create();
    if (_isDisposed) {
      AppError.fireAndForget(
        _channel.disposePlayer(playerId),
        action: 'nativeAvPlayer.disposeLateCreatedPlayer',
      );
      return;
    }
    _playerId = playerId;

    // 监听事件
    _eventSubscription = _channel.eventStream
        .where((event) => event.playerId == _playerId)
        .listen(_handleEvent);

    _isInitialized = true;
    logger.i('NativeAVPlayerBackend: 初始化完成 (playerId: $_playerId)');
  }

  Future<void> _ensureInitialized() async {
    await _initFuture;
    if (_isDisposed) {
      throw StateError('NativeAVPlayerBackend has been disposed');
    }
    if (_playerId == 0) {
      throw StateError('NativeAVPlayerBackend failed to initialize');
    }
  }

  void _handleEvent(NativeAVPlayerEvent event) {
    if (_isDisposed) return;

    switch (event.type) {
      case NativeAVPlayerEventType.playingChanged:
        _isPlaying = event.data['isPlaying'] as bool? ?? false;
        _playingController.add(_isPlaying);

      case NativeAVPlayerEventType.bufferingChanged:
        _isBuffering = event.data['isBuffering'] as bool? ?? false;
        _bufferingController.add(_isBuffering);

      case NativeAVPlayerEventType.positionChanged:
        final positionMs = event.data['position'] as int? ?? 0;
        _position = Duration(milliseconds: positionMs);
        _positionController.add(_position);

      case NativeAVPlayerEventType.durationChanged:
        final durationMs = event.data['duration'] as int? ?? 0;
        _duration = Duration(milliseconds: durationMs);
        _durationController.add(_duration);

      case NativeAVPlayerEventType.videoSizeChanged:
        _videoWidth = event.data['width'] as int?;
        _videoHeight = event.data['height'] as int?;

      case NativeAVPlayerEventType.completed:
        _completedController.add(true);

      case NativeAVPlayerEventType.error:
        final message = event.data['message'] as String?;
        _errorController.add(message);

      case NativeAVPlayerEventType.audioTrackChanged:
        _currentAudioTrackIndex = event.data['index'] as int? ?? -1;

      case NativeAVPlayerEventType.subtitleTrackChanged:
        _currentSubtitleTrackIndex = event.data['index'] as int? ?? -1;

      case NativeAVPlayerEventType.pipDidStart:
        _isPiPActive = true;

      case NativeAVPlayerEventType.pipDidStop:
        _isPiPActive = false;

      default:
        break;
    }
  }

  // ==================== VideoPlayerBackend 实现 ====================

  @override
  PlayerBackendType get type => PlayerBackendType.nativeAVPlayer;

  @override
  bool get isInitialized => _isInitialized;

  @override
  bool get isDisposed => _isDisposed;

  @override
  Future<void> open(String url, {Map<String, String>? headers}) async {
    await _ensureInitialized();
    logger.i('NativeAVPlayerBackend: 打开视频 $url');
    await _channel.open(_playerId, url, headers: headers);
  }

  @override
  Future<void> close() async {
    await _ensureInitialized();
    await _channel.pause(_playerId);
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    _eventSubscription?.cancel();
    _eventSubscription = null;

    if (_playerId != 0) {
      _channel.disposePlayer(_playerId);
    }

    _playingController.close();
    _bufferingController.close();
    _positionController.close();
    _durationController.close();
    _volumeController.close();
    _speedController.close();
    _errorController.close();
    _completedController.close();
    _audioTracksController.close();
    _subtitleTracksController.close();

    logger.d('NativeAVPlayerBackend: 已销毁');
  }

  @override
  Future<void> play() async {
    await _ensureInitialized();
    await _channel.play(_playerId);
  }

  @override
  Future<void> pause() async {
    await _ensureInitialized();
    await _channel.pause(_playerId);
  }

  @override
  Future<void> playOrPause() async {
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    await _ensureInitialized();
    await _channel.seek(_playerId, position.inMilliseconds);
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _ensureInitialized();
    _speed = speed;
    await _channel.setSpeed(_playerId, speed);
    _speedController.add(speed);
  }

  @override
  Future<void> setVolume(double volume) async {
    await _ensureInitialized();
    _volume = volume;
    await _channel.setVolume(_playerId, volume);
    _volumeController.add(volume);
  }

  @override
  Future<List<AudioTrackInfo>> getAudioTracks() async {
    await _ensureInitialized();
    final tracks = await _channel.getAudioTracks(_playerId);
    return tracks
        .map(
          (t) => AudioTrackInfo(
            index: t['index'] as int? ?? 0,
            id: t['id'] as String? ?? '',
            title: t['title'] as String?,
            language: t['language'] as String?,
          ),
        )
        .toList();
  }

  @override
  Future<void> setAudioTrack(int index) async {
    await _ensureInitialized();
    await _channel.setAudioTrack(_playerId, index);
    _currentAudioTrackIndex = index;
  }

  @override
  int? get currentAudioTrackIndex =>
      _currentAudioTrackIndex >= 0 ? _currentAudioTrackIndex : null;

  @override
  Future<List<SubtitleTrackInfo>> getSubtitleTracks() async {
    await _ensureInitialized();
    final tracks = await _channel.getSubtitleTracks(_playerId);
    return tracks
        .map(
          (t) => SubtitleTrackInfo(
            index: t['index'] as int? ?? 0,
            id: t['id'] as String? ?? '',
            title: t['title'] as String?,
            language: t['language'] as String?,
            isForced: t['isForced'] as bool? ?? false,
          ),
        )
        .toList();
  }

  @override
  Future<void> setSubtitleTrack(int index) async {
    await _ensureInitialized();
    await _channel.setSubtitleTrack(_playerId, index);
    _currentSubtitleTrackIndex = index;
  }

  @override
  Future<void> disableSubtitle() async {
    await _ensureInitialized();
    await _channel.disableSubtitle(_playerId);
    _currentSubtitleTrackIndex = -1;
  }

  @override
  Future<void> loadExternalSubtitle(String url, {String? title}) async {
    try {
      await _ensureInitialized();
      final index = await _channel.loadExternalSubtitle(
        _playerId,
        url,
        title: title,
      );
      if (index != null && index >= 0) {
        _currentSubtitleTrackIndex = index;
        logger.i('NativeAVPlayerBackend: 外部字幕已加载 (index: $index) $url');
      } else {
        // 原生侧返回 null 表示未实现/不支持，保持当前行为不变
        logger.w('NativeAVPlayerBackend: 外部字幕加载未生效（原生侧未实现或不支持）');
      }
    } on MissingPluginException catch (e, st) {
      // 原生方法尚未实现：降级为无操作，不影响播放
      AppError.ignore(e, st, '原生外部字幕方法未实现（降级忽略）');
    } on PlatformException catch (e, st) {
      AppError.ignore(e, st, '原生外部字幕加载失败（降级忽略）');
    }
  }

  @override
  int get currentSubtitleTrackIndex => _currentSubtitleTrackIndex;

  @override
  // iOS 9+ 和 macOS 12+ 支持画中画
  Future<bool> get isPipSupported async => Platform.isIOS || Platform.isMacOS;

  @override
  Future<bool> enterPictureInPicture() async {
    await _ensureInitialized();
    return _channel.enterPiP(_playerId);
  }

  @override
  Future<bool> exitPictureInPicture() async {
    await _ensureInitialized();
    return _channel.exitPiP(_playerId);
  }

  @override
  bool get isPictureInPicture => _isPiPActive;

  @override
  Future<List<int>?> screenshot() async {
    await _ensureInitialized();
    return _channel.screenshot(_playerId);
  }

  // ==================== 状态流 ====================

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Stream<bool> get bufferingStream => _bufferingController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration> get durationStream => _durationController.stream;

  @override
  Stream<double> get volumeStream => _volumeController.stream;

  @override
  Stream<double> get speedStream => _speedController.stream;

  @override
  Stream<String?> get errorStream => _errorController.stream;

  @override
  Stream<bool> get completedStream => _completedController.stream;

  @override
  Stream<List<AudioTrackInfo>> get audioTracksStream =>
      _audioTracksController.stream;

  @override
  Stream<List<SubtitleTrackInfo>> get subtitleTracksStream =>
      _subtitleTracksController.stream;

  // ==================== 当前状态 ====================

  @override
  bool get isPlaying => _isPlaying;

  @override
  bool get isBuffering => _isBuffering;

  @override
  Duration get position => _position;

  @override
  Duration get duration => _duration;

  @override
  double get volume => _volume;

  @override
  double get speed => _speed;

  @override
  int? get videoWidth => _videoWidth;

  @override
  int? get videoHeight => _videoHeight;

  @override
  double get aspectRatio {
    final w = _videoWidth;
    final h = _videoHeight;
    if (w != null && h != null && h > 0) {
      return w / h;
    }
    return 16 / 9;
  }

  /// 获取播放器 ID（用于 Platform View）
  int get playerId => _playerId;

  // ==================== 视图 ====================

  @override
  Widget buildVideoWidget({BoxFit fit = BoxFit.contain}) =>
      NativeAVPlayerView(playerId: _playerId, fit: fit);
}
