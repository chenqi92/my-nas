import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/pip_service.dart';
import 'package:my_nas/features/video/data/services/player/video_player_backend.dart';

/// media_kit 播放器后端实现
///
/// 封装 media_kit (MPV/libmpv) 作为播放器后端
class MediaKitBackend implements VideoPlayerBackend {
  MediaKitBackend() {
    _init();
  }

  late final Player _player;
  late final VideoController _videoController;
  final PipService _pipService = PipService();

  bool _isInitialized = false;
  bool _isDisposed = false;
  int _currentAudioTrackIndex = -1;
  int _currentSubtitleTrackIndex = -1;

  // Stream controllers for unified interface
  final _playingController = StreamController<bool>.broadcast();
  final _bufferingController = StreamController<bool>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _volumeController = StreamController<double>.broadcast();
  final _speedController = StreamController<double>.broadcast();
  final _errorController = StreamController<String?>.broadcast();
  final _completedController = StreamController<bool>.broadcast();
  final _audioTracksController = StreamController<List<AudioTrackInfo>>.broadcast();
  final _subtitleTracksController = StreamController<List<SubtitleTrackInfo>>.broadcast();

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  /// 获取底层 Player 实例（用于高级操作）
  Player get player => _player;

  /// 获取底层 VideoController（用于渲染）
  VideoController get videoController => _videoController;

  void _init() {
    _player = Player();
    _videoController = VideoController(_player);
    _setupStreamListeners();
    _isInitialized = true;
    logger.d('MediaKitBackend: 初始化完成');
  }

  void _setupStreamListeners() {
    _subscriptions
      ..add(_player.stream.playing.listen((playing) {
        if (!_isDisposed) _playingController.add(playing);
      }))
      ..add(_player.stream.buffering.listen((buffering) {
        if (!_isDisposed) _bufferingController.add(buffering);
      }))
      ..add(_player.stream.position.listen((position) {
        if (!_isDisposed) _positionController.add(position);
      }))
      ..add(_player.stream.duration.listen((duration) {
        if (!_isDisposed) _durationController.add(duration);
      }))
      ..add(_player.stream.volume.listen((volume) {
        if (!_isDisposed) _volumeController.add(volume / 100);
      }))
      ..add(_player.stream.rate.listen((rate) {
        if (!_isDisposed) _speedController.add(rate);
      }))
      ..add(_player.stream.error.listen((error) {
        if (!_isDisposed && error.isNotEmpty) {
          _errorController.add(error);
        }
      }))
      ..add(_player.stream.completed.listen((completed) {
        if (!_isDisposed) _completedController.add(completed);
      }))
      ..add(_player.stream.tracks.listen((tracks) {
        if (_isDisposed) return;

        // 转换音轨列表
        final audioTracks = tracks.audio
            .asMap()
            .entries
            .map((e) => AudioTrackInfo(
                  index: e.key,
                  id: e.value.id,
                  title: e.value.title,
                  language: e.value.language,
                ))
            .toList();
        _audioTracksController.add(audioTracks);

        // 转换字幕轨道列表
        final subtitleTracks = tracks.subtitle
            .asMap()
            .entries
            .map((e) => SubtitleTrackInfo(
                  index: e.key,
                  id: e.value.id,
                  title: e.value.title,
                  language: e.value.language,
                ))
            .toList();
        _subtitleTracksController.add(subtitleTracks);
      }));
  }

  // ==================== VideoPlayerBackend 实现 ====================

  @override
  PlayerBackendType get type => PlayerBackendType.mediaKit;

  @override
  bool get isInitialized => _isInitialized;

  @override
  bool get isDisposed => _isDisposed;

  @override
  Future<void> open(String url, {Map<String, String>? headers}) async {
    logger.i('MediaKitBackend: 打开视频 $url');
    await _player.open(Media(url, httpHeaders: headers ?? {}));
  }

  @override
  Future<void> close() async {
    await _player.stop();
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();

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

    _player.dispose();
    logger.d('MediaKitBackend: 已销毁');
  }

  @override
  Future<void> play() async => _player.play();

  @override
  Future<void> pause() async => _player.pause();

  @override
  Future<void> playOrPause() async => _player.playOrPause();

  @override
  Future<void> seek(Duration position) async => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) async => _player.setRate(speed);

  @override
  Future<void> setVolume(double volume) async =>
      _player.setVolume(volume * 100);

  @override
  Future<List<AudioTrackInfo>> getAudioTracks() async => _player.state.tracks.audio
        .asMap()
        .entries
        .map((e) => AudioTrackInfo(
              index: e.key,
              id: e.value.id,
              title: e.value.title,
              language: e.value.language,
            ))
        .toList();

  @override
  Future<void> setAudioTrack(int index) async {
    final tracks = _player.state.tracks.audio;
    if (index >= 0 && index < tracks.length) {
      await _player.setAudioTrack(tracks[index]);
      _currentAudioTrackIndex = index;
      logger.d('MediaKitBackend: 设置音轨 index=$index');
    }
  }

  @override
  int? get currentAudioTrackIndex {
    final currentTrack = _player.state.track.audio;
    final tracks = _player.state.tracks.audio;
    final index = tracks.indexWhere((t) => t.id == currentTrack.id);
    return index >= 0 ? index : _currentAudioTrackIndex;
  }

  @override
  Future<List<SubtitleTrackInfo>> getSubtitleTracks() async => _player.state.tracks.subtitle
        .asMap()
        .entries
        .map((e) => SubtitleTrackInfo(
              index: e.key,
              id: e.value.id,
              title: e.value.title,
              language: e.value.language,
            ))
        .toList();

  @override
  Future<void> setSubtitleTrack(int index) async {
    final tracks = _player.state.tracks.subtitle;
    if (index >= 0 && index < tracks.length) {
      await _player.setSubtitleTrack(tracks[index]);
      _currentSubtitleTrackIndex = index;
      logger.d('MediaKitBackend: 设置字幕轨道 index=$index');
    }
  }

  @override
  Future<void> disableSubtitle() async {
    await _player.setSubtitleTrack(SubtitleTrack.no());
    _currentSubtitleTrackIndex = -1;
  }

  @override
  Future<void> loadExternalSubtitle(String url, {String? title}) async {
    await _player.setSubtitleTrack(SubtitleTrack.uri(url, title: title));
    logger.d('MediaKitBackend: 加载外部字幕 $url');
  }

  @override
  int get currentSubtitleTrackIndex {
    final currentTrack = _player.state.track.subtitle;
    final tracks = _player.state.tracks.subtitle;
    final index = tracks.indexWhere((t) => t.id == currentTrack.id);
    return index >= 0 ? index : _currentSubtitleTrackIndex;
  }

  @override
  Future<bool> get isPipSupported => _pipService.isSupported;

  @override
  Future<bool> enterPictureInPicture() async => _pipService.enterPipMode(aspectRatio: aspectRatio);

  @override
  Future<bool> exitPictureInPicture() async => _pipService.exitPipMode();

  @override
  bool get isPictureInPicture => _pipService.isPipMode;

  @override
  Future<List<int>?> screenshot() async => _player.screenshot();

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
  bool get isPlaying => _player.state.playing;

  @override
  bool get isBuffering => _player.state.buffering;

  @override
  Duration get position => _player.state.position;

  @override
  Duration get duration => _player.state.duration;

  @override
  double get volume => _player.state.volume / 100;

  @override
  double get speed => _player.state.rate;

  @override
  int? get videoWidth => _player.state.width;

  @override
  int? get videoHeight => _player.state.height;

  @override
  double get aspectRatio {
    final w = _player.state.width;
    final h = _player.state.height;
    if (w != null && h != null && h > 0) {
      return w / h;
    }
    return 16 / 9;
  }

  // ==================== 视图 ====================

  @override
  Widget buildVideoWidget({BoxFit fit = BoxFit.contain}) => Video(
      controller: _videoController,
      fit: fit,
      // 禁用内置字幕渲染，使用自定义字幕覆盖层
      subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
    );
}
