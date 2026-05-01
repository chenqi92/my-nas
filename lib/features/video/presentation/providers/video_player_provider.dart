import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/services/media_proxy_server.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/transfer/presentation/providers/transfer_provider.dart';
import 'package:my_nas/features/video/data/services/audio_track_service.dart';
import 'package:my_nas/features/video/data/services/capability/playback_capability_service.dart';
import 'package:my_nas/features/video/data/services/pip_service.dart';
import 'package:my_nas/features/video/data/services/player/dolby_vision_detector.dart';
import 'package:my_nas/features/video/data/services/player/native_av_player_backend.dart';
import 'package:my_nas/features/video/data/services/player/video_player_backend.dart';
import 'package:my_nas/features/video/data/services/subtitle_service.dart';
import 'package:my_nas/features/video/data/services/media_server_playback_reporter.dart';
import 'package:my_nas/features/video/data/services/video_history_service.dart';
import 'package:my_nas/features/video/data/services/video_thumbnail_service.dart';
import 'package:my_nas/features/video/domain/entities/audio_capability.dart';
import 'package:my_nas/features/video/domain/entities/hdr_capability.dart';
import 'package:my_nas/features/video/domain/entities/playback_configuration.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/data/services/trakt_scrobble_service.dart';
import 'package:my_nas/features/media_tracking/presentation/providers/trakt_sync_provider.dart';
import 'package:my_nas/features/video/presentation/providers/hdr_audio_settings_provider.dart';
import 'package:my_nas/features/video/presentation/providers/playback_settings_provider.dart';
import 'package:my_nas/features/video/presentation/providers/playlist_provider.dart';
import 'package:my_nas/features/video/presentation/providers/quality_provider.dart';

/// 当前播放的视频（autoDispose: 离开播放器页面后自动清理）
final currentVideoProvider = StateProvider.autoDispose<VideoItem?>((ref) => null);

/// 视频播放器控制器（autoDispose: 离开播放器页面后自动清理资源）
final videoPlayerControllerProvider =
    StateNotifierProvider.autoDispose<VideoPlayerNotifier, VideoPlayerState>(VideoPlayerNotifier.new);

/// 可用字幕列表（autoDispose）
final availableSubtitlesProvider = StateProvider.autoDispose<List<SubtitleItem>>((ref) => []);

/// 当前选中的字幕（需要持久化，不使用 autoDispose）
final currentSubtitleProvider = StateProvider<SubtitleItem?>((ref) => null);

/// 当前选中的内嵌字幕轨道 ID（需要持久化，不使用 autoDispose）
/// 用于跟踪内嵌字幕的选中状态
final currentEmbeddedSubtitleIdProvider = StateProvider<String?>((ref) => null);

/// 播放器状态
class VideoPlayerState {
  const VideoPlayerState({
    this.isPlaying = false,
    this.isBuffering = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 1.0,
    this.speed = 1.0,
    this.isFullscreen = false,
    this.isPictureInPicture = false,
    this.subtitleEnabled = true,
    this.errorMessage,
    this.positionOffset = Duration.zero,
    this.originalDuration = Duration.zero,
    this.backendType = PlayerBackendType.mediaKit,
  });

  final bool isPlaying;
  final bool isBuffering;
  /// 播放器报告的原始位置（转码流从 0 开始）
  final Duration position;
  /// 转码流的时长（转码后的文件长度）
  final Duration duration;
  final double volume;
  final double speed;
  final bool isFullscreen;
  final bool isPictureInPicture;
  final bool subtitleEnabled;
  final String? errorMessage;
  /// 位置偏移量（转码起始位置）
  final Duration positionOffset;
  /// 原始视频总时长（用于进度条显示）
  final Duration originalDuration;
  /// 当前使用的播放器后端类型
  final PlayerBackendType backendType;

  /// 是否使用原生 AVPlayer（杜比视界）
  bool get isUsingNativePlayer => backendType == PlayerBackendType.nativeAVPlayer;

  /// 实际播放位置（播放器位置 + 偏移量）
  Duration get actualPosition => position + positionOffset;

  /// 显示用的总时长（如果有原始时长则使用原始时长）
  Duration get displayDuration =>
      originalDuration > Duration.zero ? originalDuration : duration + positionOffset;

  /// 实际进度（基于原始视频时长）
  double get progress =>
      displayDuration.inMilliseconds > 0
          ? actualPosition.inMilliseconds / displayDuration.inMilliseconds
          : 0;

  String get positionText => _formatDuration(actualPosition);
  String get durationText => _formatDuration(displayDuration);

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  VideoPlayerState copyWith({
    bool? isPlaying,
    bool? isBuffering,
    Duration? position,
    Duration? duration,
    double? volume,
    double? speed,
    bool? isFullscreen,
    bool? isPictureInPicture,
    bool? subtitleEnabled,
    String? errorMessage,
    Duration? positionOffset,
    Duration? originalDuration,
    PlayerBackendType? backendType,
  }) =>
      VideoPlayerState(
        isPlaying: isPlaying ?? this.isPlaying,
        isBuffering: isBuffering ?? this.isBuffering,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        volume: volume ?? this.volume,
        speed: speed ?? this.speed,
        isFullscreen: isFullscreen ?? this.isFullscreen,
        isPictureInPicture: isPictureInPicture ?? this.isPictureInPicture,
        subtitleEnabled: subtitleEnabled ?? this.subtitleEnabled,
        errorMessage: errorMessage,
        positionOffset: positionOffset ?? this.positionOffset,
        originalDuration: originalDuration ?? this.originalDuration,
        backendType: backendType ?? this.backendType,
      );
}

/// 视频播放器管理
class VideoPlayerNotifier extends StateNotifier<VideoPlayerState> {
  VideoPlayerNotifier(this._ref) : super(const VideoPlayerState()) {
    _initPlayer();
  }

  final Ref _ref;
  late final Player _player;
  late final VideoController _videoController;
  final VideoHistoryService _historyService = VideoHistoryService();
  final VideoThumbnailService _thumbnailService = VideoThumbnailService();
  final AudioTrackService _audioTrackService = AudioTrackService();
  final PipService _pipService = PipService();
  final PlaybackCapabilityService _capabilityService = PlaybackCapabilityService();

  /// 原生 AVPlayer 后端（用于 iOS/macOS 杜比视界）
  NativeAVPlayerBackend? _nativeBackend;

  /// 原生播放器事件订阅
  final List<StreamSubscription<dynamic>> _nativeSubscriptions = [];

  /// 是否已经自动选择过音轨（每个视频只选择一次）
  bool _hasAutoSelectedAudioTrack = false;

  Timer? _progressSaveTimer;
  VideoItem? _currentVideo;

  /// 进度保存计数器（用于控制截图频率）
  int _progressSaveCount = 0;

  // Stream subscriptions 管理
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _isDisposed = false;

  Player get player => _player;
  VideoController get videoController => _videoController;

  /// 获取原生播放器后端（仅在使用原生播放器时有效）
  NativeAVPlayerBackend? get nativeBackend => _nativeBackend;

  /// 获取当前使用的播放器后端类型
  PlayerBackendType get currentBackendType => state.backendType;

  /// 是否正在使用原生 AVPlayer
  bool get isUsingNativePlayer =>
      state.backendType == PlayerBackendType.nativeAVPlayer && _nativeBackend != null;

  /// 获取视频显示组件
  ///
  /// 根据当前后端类型返回对应的视频显示组件
  Widget buildVideoWidget({BoxFit fit = BoxFit.contain}) {
    if (isUsingNativePlayer && _nativeBackend != null) {
      return _nativeBackend!.buildVideoWidget(fit: fit);
    }
    // 默认使用 media_kit 的 Video widget
    return Video(controller: _videoController, fit: fit);
  }

  /// 是否支持画中画
  Future<bool> get isPipSupported => _pipService.isSupported;

  /// 清理原生播放器后端
  Future<void> _cleanupNativeBackend() async {
    // 取消原生播放器事件订阅
    for (final subscription in _nativeSubscriptions) {
      await subscription.cancel();
    }
    _nativeSubscriptions.clear();

    // 销毁原生播放器
    if (_nativeBackend != null) {
      _nativeBackend!.dispose();
      _nativeBackend = null;
    }
  }

  /// 订阅原生播放器事件
  void _subscribeToNativeBackendStreams() {
    if (_nativeBackend == null) return;

    _nativeSubscriptions
      ..add(_nativeBackend!.playingStream.listen((playing) {
        if (_isDisposed) return;
        state = state.copyWith(isPlaying: playing);
        if (playing) {
          _startProgressSaveTimer();
        } else {
          _stopProgressSaveTimer();
          _saveCurrentProgress();
        }
      }))
      ..add(_nativeBackend!.bufferingStream.listen((buffering) {
        if (_isDisposed) return;
        state = state.copyWith(isBuffering: buffering);
      }))
      ..add(_nativeBackend!.positionStream.listen((position) {
        if (_isDisposed) return;
        state = state.copyWith(position: position);
      }))
      ..add(_nativeBackend!.durationStream.listen((duration) {
        if (_isDisposed) return;
        state = state.copyWith(duration: duration);
      }))
      ..add(_nativeBackend!.errorStream.listen((error) {
        if (_isDisposed) return;
        if (error != null && error.isNotEmpty) {
          state = state.copyWith(errorMessage: error);
        }
      }))
      ..add(_nativeBackend!.completedStream.listen((completed) {
        if (_isDisposed) return;
        if (completed && _currentVideo != null) {
          _historyService.clearProgress(_currentVideo!.path);
          logger.d('VideoPlayerNotifier: 播放完成，清除进度');
          // 上报 Trakt Scrobble（播放完成 = 100% 进度）
          _reportTraktComplete();
          _playNextFromPlaylist();
        }
      }));

    logger.d('VideoPlayerNotifier: 已订阅原生播放器事件');
  }

  void _initPlayer() {
    _player = Player();
    _videoController = VideoController(_player);

    // 初始化服务
    _historyService.init();
    _thumbnailService.init();

    // 应用保存的设置
    _applySettings();

    // 监听播放状态
    _subscriptions..add(_player.stream.playing.listen((playing) {
      if (_isDisposed) return;
      state = state.copyWith(isPlaying: playing);

      // 开始播放时启动进度保存定时器
      if (playing) {
        _startProgressSaveTimer();
      } else {
        _stopProgressSaveTimer();
        // 暂停时保存一次进度
        _saveCurrentProgress();
      }
    }))

    // 监听缓冲状态
    ..add(_player.stream.buffering.listen((buffering) {
      if (_isDisposed) return;
      state = state.copyWith(isBuffering: buffering);
    }))

    // 监听播放位置
    ..add(_player.stream.position.listen((position) {
      if (_isDisposed) return;
      state = state.copyWith(position: position);
    }))

    // 监听总时长
    ..add(_player.stream.duration.listen((duration) {
      if (_isDisposed) return;
      state = state.copyWith(duration: duration);
    }))

    // 监听音量
    ..add(_player.stream.volume.listen((volume) {
      if (_isDisposed) return;
      state = state.copyWith(volume: volume / 100);
    }))

    // 监听倍速
    ..add(_player.stream.rate.listen((rate) {
      if (_isDisposed) return;
      state = state.copyWith(speed: rate);
    }))

    // 监听错误
    ..add(_player.stream.error.listen((error) {
      if (_isDisposed) return;
      if (error.isNotEmpty) {
        state = state.copyWith(errorMessage: error);
      }
    }))

    // 监听播放完成
    ..add(_player.stream.completed.listen((completed) {
      if (_isDisposed) return;
      if (completed && _currentVideo != null) {
        // 播放完成，清除进度
        _historyService.clearProgress(_currentVideo!.path);
        logger.d('VideoPlayerNotifier: 播放完成，清除进度');

        // 上报 Trakt Scrobble（播放完成 = 100% 进度）
        _reportTraktComplete();

        // 尝试播放下一个
        _playNextFromPlaylist();
      }
    }))

    // 监听音轨列表变化，自动选择最佳音轨
    ..add(_player.stream.tracks.listen((tracks) {
      if (_isDisposed) return;
      if (!_hasAutoSelectedAudioTrack && tracks.audio.length > 1) {
        _autoSelectAudioTrack(tracks.audio);
      }
    }));
  }

  /// 自动选择最佳音轨
  Future<void> _autoSelectAudioTrack(List<AudioTrack> tracks) async {
    if (_hasAutoSelectedAudioTrack) return;
    _hasAutoSelectedAudioTrack = true;

    final bestTrack = _audioTrackService.selectBestAudioTrack(tracks);
    if (bestTrack != null) {
      // 检查是否需要切换（如果当前音轨已经是最佳音轨则不切换）
      final currentTrack = _player.state.track.audio;
      if (currentTrack.id != bestTrack.id) {
        await setAudioTrack(bestTrack);
        logger.i('VideoPlayerNotifier: 自动选择音轨 ${bestTrack.title ?? bestTrack.id}');
      }
    }
  }

  /// 应用 HDR 和音频直通配置
  ///
  /// 根据用户设置和设备能力，配置 MPV 的 HDR 和音频直通参数
  Future<void> _applyHdrAudioConfiguration() async {
    try {
      // 获取用户设置
      final settingsState = _ref.read(hdrAudioSettingsProvider);
      final userSettings = settingsState.settings;

      // 获取设备能力（使用缓存）
      final hdrCapability = settingsState.hdrCapability ??
          await _capabilityService.getHdrCapability();
      final audioCapability = settingsState.audioCapability ??
          await _capabilityService.getAudioCapability();

      // 生成播放配置
      // 注意：由于此时视频还未加载，我们无法知道视频的 HDR/音频信息
      // 因此使用默认的 VideoMediaInfo（假设可能是 HDR/高级音频）
      // 这样配置会在视频是 HDR 时启用直通，在视频是 SDR 时 MPV 会自动忽略相关设置
      final videoInfo = VideoMediaInfo(
        isHdr: userSettings.hdrMode == HdrMode.auto ||
            userSettings.hdrMode == HdrMode.passthrough,
        hdrType: HdrType.hdr10, // 假设可能是 HDR10（最常见的格式）
        audioCodec: AudioCodec.eac3, // 假设可能是 EAC3（支持 Dolby Atmos）
        audioChannels: 8,
      );

      final config = _capabilityService.generateConfiguration(
        videoInfo: videoInfo,
        hdrCapability: hdrCapability,
        audioCapability: audioCapability,
        userSettings: userSettings,
      );

      // 应用配置到播放器
      await _capabilityService.applyConfiguration(_player, config);

      logger.i('VideoPlayer: HDR/音频配置已应用 - $config');
    } catch (e, st) {
      // 配置失败不影响正常播放
      AppError.ignore(e, st, 'HDR/音频配置应用失败（非关键错误）');
    }
  }

  /// 应用保存的设置
  Future<void> _applySettings() async {
    final settings = _ref.read(playbackSettingsProvider);
    await _player.setVolume(settings.volume * 100);
    await _player.setRate(settings.speed);
    state = state.copyWith(volume: settings.volume, speed: settings.speed);
    logger.i('VideoPlayerNotifier: 应用设置 volume=${settings.volume}, speed=${settings.speed}');
  }

  /// 重新初始化 stream listeners（在 stopSync 后再次播放时调用）
  void _reinitStreamListeners() {
    // 确保先清理旧的订阅
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions..clear()

    // 重新添加所有 stream listeners
    ..add(_player.stream.playing.listen((playing) {
      if (_isDisposed) return;
      state = state.copyWith(isPlaying: playing);
      if (playing) {
        _startProgressSaveTimer();
      } else {
        _stopProgressSaveTimer();
        _saveCurrentProgress();
      }
    }))

    ..add(_player.stream.buffering.listen((buffering) {
      if (_isDisposed) return;
      state = state.copyWith(isBuffering: buffering);
    }))

    ..add(_player.stream.position.listen((position) {
      if (_isDisposed) return;
      state = state.copyWith(position: position);
    }))

    ..add(_player.stream.duration.listen((duration) {
      if (_isDisposed) return;
      state = state.copyWith(duration: duration);
    }))

    ..add(_player.stream.volume.listen((volume) {
      if (_isDisposed) return;
      state = state.copyWith(volume: volume / 100);
    }))

    ..add(_player.stream.rate.listen((rate) {
      if (_isDisposed) return;
      state = state.copyWith(speed: rate);
    }))

    ..add(_player.stream.error.listen((error) {
      if (_isDisposed) return;
      if (error.isNotEmpty) {
        state = state.copyWith(errorMessage: error);
      }
    }))

    ..add(_player.stream.completed.listen((completed) {
      if (_isDisposed) return;
      if (completed && _currentVideo != null) {
        _historyService.clearProgress(_currentVideo!.path);
        logger.d('VideoPlayerNotifier: 播放完成，清除进度');
        _playNextFromPlaylist();
      }
    }))

    ..add(_player.stream.tracks.listen((tracks) {
      if (_isDisposed) return;
      if (!_hasAutoSelectedAudioTrack && tracks.audio.length > 1) {
        _autoSelectAudioTrack(tracks.audio);
      }
    }));

    logger.d('VideoPlayerNotifier: 重新初始化 stream listeners');
  }

  /// 尝试从播放列表播放下一个
  Future<void> _playNextFromPlaylist() async {
    final playlist = _ref.read(playlistProvider);

    // 检查单曲循环
    if (playlist.repeatMode == VideoRepeatMode.one && _currentVideo != null) {
      await play(_currentVideo!, startPosition: Duration.zero);
      return;
    }

    // 播放下一个
    final nextVideo = _ref.read(playlistProvider.notifier).playNext();
    if (nextVideo != null) {
      await play(nextVideo);
    }
  }

  void _startProgressSaveTimer() {
    _stopProgressSaveTimer();
    // 每10秒保存一次进度
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _saveCurrentProgress();
    });
  }

  void _stopProgressSaveTimer() {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = null;
  }

  Future<void> _saveCurrentProgress() async {
    if (_currentVideo == null) {
      logger.d('VideoPlayerNotifier: 保存进度跳过 - 无当前视频');
      return;
    }
    // 使用实际位置（包含偏移量）
    final actualPos = state.actualPosition;
    final totalDuration = state.displayDuration;

    if (actualPos.inSeconds < 5) {
      logger.d('VideoPlayerNotifier: 保存进度跳过 - 位置小于5秒');
      return;
    }
    if (totalDuration.inSeconds < 10) {
      logger.d('VideoPlayerNotifier: 保存进度跳过 - 时长小于10秒');
      return;
    }

    logger.d('VideoPlayerNotifier: 保存进度 ${_currentVideo!.path} => ${actualPos.inSeconds}s / ${totalDuration.inSeconds}s');
    await _historyService.saveProgress(
      videoPath: _currentVideo!.path,
      position: actualPos,
      duration: totalDuration,
    );

    // 上报媒体服务器播放进度
    final reporter = _ref.read(mediaServerPlaybackReporterProvider);
    if (reporter.hasActiveSession) {
      await reporter.reportProgress(
        positionTicks: actualPos.inMicroseconds * 10,
        isPaused: !state.isPlaying,
      );
    }

    // 每3次保存进度时（每30秒），同时保存进度截图
    _progressSaveCount++;
    if (_progressSaveCount >= 3) {
      _progressSaveCount = 0;
      // 异步保存截图，不阻塞进度保存
      AppError.fireAndForget(
        _captureProgressThumbnail(),
        action: 'periodicProgressThumbnail',
      );
    }
  }

  /// 播放视频
  Future<void> play(VideoItem video, {Duration? startPosition}) async {
    // 如果之前已停止，需要重新初始化 stream listeners
    if (_isDisposed) {
      _isDisposed = false;
      _reinitStreamListeners();
    }

    // 保存当前视频进度
    await _saveCurrentProgress();

    // 清理之前的原生后端
    await _cleanupNativeBackend();

    // 重置自动选择标志（新视频需要重新选择音轨）
    _hasAutoSelectedAudioTrack = false;

    // 重置字幕状态（新视频需要重新加载字幕）
    _ref.read(currentSubtitleProvider.notifier).state = null;
    _ref.read(availableSubtitlesProvider.notifier).state = [];

    _currentVideo = video;
    _ref.read(currentVideoProvider.notifier).state = video;

    // 重置偏移量（新视频从头播放，没有转码偏移）
    state = state.copyWith(
      positionOffset: Duration.zero,
      originalDuration: Duration.zero,
    );

    logger..i('VideoPlayer: 开始播放 ${video.name}')
    ..d('VideoPlayer: URL => ${video.url}')
    ..d('VideoPlayer: size=${video.size}, path=${video.path}');

    // 先检查是否有缓存文件（优先使用离线缓存）
    String? playUrl;
    var resolvedVideo = video;

    if (video.sourceId != null) {
      try {
        final cacheService = _ref.read(mediaCacheServiceProvider);
        await cacheService.init();
        final cachedPath = await cacheService.getCachedPath(video.sourceId!, video.path);
        if (cachedPath != null) {
          playUrl = cachedPath;
          logger.i('VideoPlayer: 使用缓存文件 => $cachedPath');
        }
      } on Exception catch (e) {
        logger.w('VideoPlayer: 检查缓存失败', e);
      }
    }

    // 如果没有缓存，走正常的 URL 获取流程
    if (playUrl == null) {
      // 如果 URL 为空，需要先获取 URL（用于播放列表中的项）
      if (video.needsUrlResolution) {
        if (video.sourceId == null) {
          logger.e('VideoPlayer: 视频缺少 sourceId，无法获取 URL');
          state = state.copyWith(errorMessage: '无法播放：缺少数据源信息');
          return;
        }

        try {
          // 先检查 NAS 连接
          final nasConnections = _ref.read(activeConnectionsProvider);
          final nasConnection = nasConnections[video.sourceId];

          // 再检查媒体服务器连接
          final mediaConnections = _ref.read(activeMediaServerConnectionsProvider);
          final mediaConnection = mediaConnections[video.sourceId];

          String? resolvedUrl;

          if (nasConnection != null && nasConnection.status == SourceStatus.connected) {
            // 使用 NAS 连接获取 URL
            resolvedUrl = await nasConnection.adapter.fileSystem.getFileUrl(video.path);
          } else if (mediaConnection != null && mediaConnection.status == SourceStatus.connected) {
            // 使用媒体服务器连接获取 URL
            resolvedUrl = await mediaConnection.adapter.virtualFileSystem.getFileUrl(video.path);

            // 上报媒体服务器播放开始
            if (video.serverItemId != null) {
              final reporter = _ref.read(mediaServerPlaybackReporterProvider);
              await reporter.reportStart(
                sourceId: video.sourceId!,
                serverItemId: video.serverItemId!,
                positionTicks: (startPosition?.inMicroseconds ?? 0) * 10,
              );
            }
          } else {
            logger.e('VideoPlayer: 数据源未连接');
            state = state.copyWith(errorMessage: '无法播放：数据源未连接');
            return;
          }

          resolvedVideo = video.copyWith(url: resolvedUrl);

          // 更新当前视频信息
          _currentVideo = resolvedVideo;
          _ref.read(currentVideoProvider.notifier).state = resolvedVideo;

          logger.i('VideoPlayer: URL 已解析 => $resolvedUrl');
        } on Exception catch (e, st) {
          AppError.handle(e, st, 'VideoPlayer.resolveUrl', {'path': video.path});
          state = state.copyWith(errorMessage: '无法获取视频地址');
          return;
        }
      }

      // 确定播放 URL（SMB 等协议需要通过代理）
      playUrl = resolvedVideo.url;
      if (resolvedVideo.needsProxy) {
        if (resolvedVideo.sourceId == null) {
          logger.e('VideoPlayer: SMB 视频缺少 sourceId，无法使用代理');
          state = state.copyWith(errorMessage: '无法播放：缺少数据源信息');
          return;
        }
        try {
          playUrl = await MediaProxyServer().registerFile(
            sourceId: resolvedVideo.sourceId!,
            filePath: resolvedVideo.path,
            fileSize: resolvedVideo.size,
          );
          logger.i('VideoPlayer: 使用代理 URL => $playUrl');
        } on Exception catch (e, st) {
          AppError.handle(e, st, 'VideoPlayer.startProxyServer');
          state = state.copyWith(errorMessage: '无法启动媒体代理服务');
          return;
        }
      }
    }

    // 确定起始位置
    var resumePosition = startPosition;

    // 如果没有指定起始位置，尝试从多个来源恢复进度
    if (resumePosition == null) {
      resumePosition = await _getResumePosition(video);
    }

    // 检测是否需要使用原生播放器（杜比视界）
    final shouldUseNative = DolbyVisionDetector.shouldUseNativePlayer(
      video: resolvedVideo,
    );

    // 标记当前使用的后端类型
    var currentBackend = PlayerBackendType.mediaKit;
    var nativePlayerFailed = false;

    // 尝试使用原生 AVPlayer（iOS/macOS 杜比视界）
    if (shouldUseNative) {
      logger.i('VideoPlayer: 检测到杜比视界内容，尝试使用原生 AVPlayer');

      try {
        _nativeBackend = NativeAVPlayerBackend();
        await _nativeBackend!.open(playUrl);
        currentBackend = PlayerBackendType.nativeAVPlayer;

        // 订阅原生播放器事件
        _subscribeToNativeBackendStreams();

        // 设置起始位置
        if (resumePosition != null && resumePosition > Duration.zero) {
          // 等待原生播放器准备好后 seek
          final completer = Completer<void>();
          StreamSubscription<Duration>? subscription;

          subscription = _nativeBackend!.durationStream.listen((duration) {
            if (duration > Duration.zero && !completer.isCompleted) {
              _nativeBackend!.seek(resumePosition!).then((_) {
                logger.i('VideoPlayerNotifier: 原生播放器跳转到 ${resumePosition!.inSeconds}s');
              });
              subscription?.cancel();
              completer.complete();
            }
          });

          // 设置超时
          Future.delayed(const Duration(seconds: 5), () {
            if (!completer.isCompleted) {
              subscription?.cancel();
              completer.complete();
              _nativeBackend!.seek(resumePosition!);
            }
          });

          await completer.future;
        }

        // 开始播放
        await _nativeBackend!.play();

        logger.i('VideoPlayer: 原生 AVPlayer 初始化成功');
      } catch (e, st) {
        // 原生播放器失败，回退到 media_kit
        logger.w('VideoPlayer: 原生 AVPlayer 初始化失败，回退到 media_kit: $e');
        AppError.ignore(e, st, '原生播放器初始化失败（回退到 media_kit）');

        await _cleanupNativeBackend();
        nativePlayerFailed = true;
        currentBackend = PlayerBackendType.mediaKit;
      }
    }

    // 使用 media_kit 播放（默认或回退）
    if (currentBackend == PlayerBackendType.mediaKit) {
      // 应用 HDR/音频配置（仅 media_kit 需要）
      await _applyHdrAudioConfiguration();

      // 打开视频并设置起始位置
      logger.d('VideoPlayer: 使用 media_kit 打开视频源...');
      try {
        await _player.open(Media(playUrl));
        logger.d('VideoPlayer: media_kit 视频源打开成功');
      } on Exception catch (e, st) {
        AppError.handle(e, st, 'VideoPlayer.openVideo', {'path': video.path});
        state = state.copyWith(errorMessage: AppError.getUserFriendlyMessage(e));
        return;
      }

      // 等待播放器准备好后再 seek
      if (resumePosition != null && resumePosition > Duration.zero) {
        // 监听 duration 变化，等视频加载完成后再 seek
        StreamSubscription<Duration>? subscription;
        final completer = Completer<void>();

        subscription = _player.stream.duration.listen((duration) {
          if (duration > Duration.zero && !completer.isCompleted) {
            // 视频已准备好，执行 seek
            _player.seek(resumePosition!).then((_) {
              logger.i('VideoPlayerNotifier: 跳转到 ${resumePosition!.inSeconds}s');
            });
            subscription?.cancel();
            completer.complete();
          }
        });

        // 设置超时，避免无限等待
        Future.delayed(const Duration(seconds: 5), () {
          if (!completer.isCompleted) {
            subscription?.cancel();
            completer.complete();
            // 超时后尝试直接 seek
            _player.seek(resumePosition!);
          }
        });

        await completer.future;
      }
    }

    // 更新后端类型状态
    state = state.copyWith(backendType: currentBackend);

    // 如果是回退到 media_kit，记录日志
    if (nativePlayerFailed) {
      logger.w('VideoPlayer: 已回退到 media_kit 播放');
    }

    // 添加到播放历史
    await _historyService.addToHistory(
      VideoHistoryItem(
        videoPath: video.path,
        videoName: video.name,
        videoUrl: video.url,
        sourceId: video.sourceId,
        thumbnailUrl: video.thumbnailUrl,
        size: video.size,
        watchedAt: DateTime.now(),
      ),
    );

    // 初始化清晰度控制器（传递代理 URL 用于转码，仅 media_kit 需要）
    if (currentBackend == PlayerBackendType.mediaKit) {
      await _initQualityController(video, playUrl: playUrl);
    }

    // 上报 Trakt Scrobble 开始
    _reportTraktStart(video);
  }

  /// 上报 Trakt Scrobble 开始播放
  void _reportTraktStart(VideoItem video) {
    final settings = _ref.read(traktScrobbleSettingsProvider);
    if (!settings.enabled) return;

    AppError.fireAndForget(
      _ref.read(traktScrobbleServiceProvider).reportStart(
            video: video,
            progress: state.progress * 100,
          ),
      action: 'traktScrobbleStart',
    );
  }

  /// 上报 Trakt Scrobble 暂停
  void _reportTraktPause() {
    final settings = _ref.read(traktScrobbleSettingsProvider);
    if (!settings.enabled) return;

    final scrobbleService = _ref.read(traktScrobbleServiceProvider);
    if (!scrobbleService.hasActiveSession) return;

    AppError.fireAndForget(
      scrobbleService.reportPause(progress: state.progress * 100),
      action: 'traktScrobblePause',
    );
  }

  /// 上报 Trakt Scrobble 停止
  void _reportTraktStop() {
    final settings = _ref.read(traktScrobbleSettingsProvider);
    if (!settings.enabled) return;

    final scrobbleService = _ref.read(traktScrobbleServiceProvider);
    if (!scrobbleService.hasActiveSession) return;

    AppError.fireAndForget(
      scrobbleService.reportStop(progress: state.progress * 100),
      action: 'traktScrobbleStop',
    );
  }

  /// 上报 Trakt Scrobble 播放完成（100% 进度）
  void _reportTraktComplete() {
    final settings = _ref.read(traktScrobbleSettingsProvider);
    if (!settings.enabled) return;

    final scrobbleService = _ref.read(traktScrobbleServiceProvider);
    if (!scrobbleService.hasActiveSession) return;

    // 播放完成，上报 100% 进度，Trakt 会自动标记为已观看
    AppError.fireAndForget(
      scrobbleService.reportStop(progress: 100.0),
      action: 'traktScrobbleComplete',
    );
  }

  /// 获取恢复播放位置
  ///
  /// 优先级：
  /// 1. Trakt 进度（如果已连接且有进度）
  /// 2. 本地进度
  Future<Duration?> _getResumePosition(VideoItem video) async {
    // 1. 尝试从 Trakt 恢复
    final traktPosition = await _getTraktResumePosition(video);
    if (traktPosition != null) {
      return traktPosition;
    }

    // 2. 尝试从本地历史恢复
    final savedProgress = await _historyService.getProgress(video.path);
    if (savedProgress != null && savedProgress.progressPercent < 0.95) {
      logger.i('VideoPlayerNotifier: 从本地历史恢复 ${savedProgress.position.inSeconds}s');
      return savedProgress.position;
    }

    return null;
  }

  /// 从 Trakt 获取恢复位置
  Future<Duration?> _getTraktResumePosition(VideoItem video) async {
    try {
      final traktSync = _ref.read(traktSyncProvider.notifier);

      // 如果未连接 Trakt，返回 null
      if (!traktSync.isConnected) return null;

      // 获取视频对应的 Trakt 进度
      final traktProgress = await traktSync.getProgressForVideo(
        video.path,
        video.sourceId ?? '',
      );

      if (traktProgress == null) return null;

      // 如果进度太低或太高，不恢复
      if (traktProgress.progress < 5 || traktProgress.progress >= 95) {
        return null;
      }

      // 需要知道视频总时长才能计算位置
      // 这里我们先返回一个占位值，实际位置将在视频加载后计算
      // 由于此时视频还没加载，我们暂时使用本地保存的时长
      final localProgress = await _historyService.getProgress(video.path);
      if (localProgress != null && localProgress.duration.inSeconds > 0) {
        final position = traktSync.progressToDuration(
          traktProgress.progress,
          localProgress.duration,
        );
        logger.i('VideoPlayerNotifier: 从 Trakt 恢复 ${position.inSeconds}s (${traktProgress.progress.toStringAsFixed(1)}%)');
        return position;
      }

      // 如果没有本地时长信息，尝试使用视频的 duration
      if (video.duration != null && video.duration!.inSeconds > 0) {
        final position = traktSync.progressToDuration(
          traktProgress.progress,
          video.duration!,
        );
        logger.i('VideoPlayerNotifier: 从 Trakt 恢复 ${position.inSeconds}s (${traktProgress.progress.toStringAsFixed(1)}%)');
        return position;
      }

      return null;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '从 Trakt 获取恢复位置失败（使用本地进度）');
      return null;
    }
  }

  /// 初始化清晰度控制器
  ///
  /// [playUrl] 可播放的 URL（可能是代理 URL 或本地文件路径），用于 FFmpeg 转码
  Future<void> _initQualityController(VideoItem video, {String? playUrl}) async {
    // 如果播放器已停止，跳过清晰度初始化
    if (_isDisposed) {
      logger.d('VideoPlayer: 播放器已停止，跳过清晰度初始化');
      return;
    }

    // 获取源类型
    SourceType sourceType = SourceType.local;
    if (video.sourceId != null) {
      final connections = _ref.read(activeConnectionsProvider);
      final connection = connections[video.sourceId];
      if (connection != null) {
        sourceType = connection.source.type;
      }
    }

    // 初始化清晰度 Provider
    // 注意: VideoItem 目前没有视频尺寸信息，传递 null 让 QualityNotifier 使用默认清晰度列表
    final qualityNotifier = _ref.read(qualityStateProvider.notifier);
    await qualityNotifier.init(
      sourceType: sourceType,
      player: _player,
      videoPath: video.path,
      videoUrl: playUrl, // 传递可访问的 URL（代理 URL 或本地路径）给 FFmpeg
    );

    // 设置清晰度切换回调
    qualityNotifier.onQualitySwitched = _onQualitySwitched;

    logger.i('VideoPlayer: 清晰度控制器已初始化, sourceType=$sourceType');
  }

  /// 清晰度切换回调 - 切换到新的转码流
  Future<void> _onQualitySwitched(String newStreamUrl) async {
    logger.i('VideoPlayer: 切换到转码流 => $newStreamUrl');

    // 保存原始视频的总时长（用于进度条显示）
    final originalDuration = state.displayDuration;

    // 获取转码起始位置（用于计算实际播放进度）
    final qualityState = _ref.read(qualityStateProvider);
    final positionOffset = qualityState.transcodingStartPosition;

    logger.d('VideoPlayer: 切换前位置 ${state.actualPosition.inSeconds}s, 偏移量 ${positionOffset.inSeconds}s');

    // 打开新的流
    try {
      await _player.open(Media(newStreamUrl));

      // 等待播放器准备好
      final completer = Completer<void>();
      StreamSubscription<Duration>? subscription;

      subscription = _player.stream.duration.listen((duration) {
        if (duration > Duration.zero && !completer.isCompleted) {
          logger.i('VideoPlayer: 转码流已就绪，时长: ${duration.inSeconds}s');
          subscription?.cancel();
          completer.complete();
        }
      });

      // 设置超时
      Future.delayed(const Duration(seconds: 5), () {
        if (!completer.isCompleted) {
          subscription?.cancel();
          completer.complete();
          logger.w('VideoPlayer: 等待转码流就绪超时');
        }
      });

      await completer.future;

      // 更新状态：设置偏移量和原始时长
      state = state.copyWith(
        positionOffset: positionOffset,
        originalDuration: originalDuration,
      );

      logger.i('VideoPlayer: 转码流切换成功，偏移量=${positionOffset.inSeconds}s，原始时长=${originalDuration.inSeconds}s');
    } catch (e, st) {
      AppError.handle(e, st, 'switchToTranscodedStream');
      state = state.copyWith(errorMessage: '切换清晰度失败: $e');
    }
  }

  /// 播放/暂停切换
  Future<void> playOrPause() async {
    if (isUsingNativePlayer && _nativeBackend != null) {
      if (state.isPlaying) {
        await _nativeBackend!.pause();
      } else {
        await _nativeBackend!.play();
      }
    } else {
      await _player.playOrPause();
    }
  }

  /// 暂停
  Future<void> pause() async {
    if (isUsingNativePlayer && _nativeBackend != null) {
      await _nativeBackend!.pause();
    } else {
      await _player.pause();
    }
    // 用户暂停时保存进度截图
    AppError.fireAndForget(
      _captureProgressThumbnail(),
      action: 'pauseProgressThumbnail',
    );
    // 上报 Trakt Scrobble 暂停
    _reportTraktPause();
  }

  /// 同步暂停（用于 dispose）
  void pauseSync() {
    if (isUsingNativePlayer && _nativeBackend != null) {
      // 原生播放器没有同步方法，使用 fire-and-forget
      AppError.fireAndForget(_nativeBackend!.pause(), action: 'nativePauseSync');
    } else {
      _player.pause();
    }
  }

  /// 继续播放
  Future<void> resume() async {
    if (isUsingNativePlayer && _nativeBackend != null) {
      await _nativeBackend!.play();
    } else {
      await _player.play();
    }
  }

  /// 停止
  Future<void> stop() async {
    // 先截图（在停止播放器之前）
    await _captureProgressThumbnail();
    await _saveCurrentProgress();
    _stopProgressSaveTimer();

    // 上报媒体服务器播放停止
    final reporter = _ref.read(mediaServerPlaybackReporterProvider);
    if (reporter.hasActiveSession) {
      final positionTicks = state.actualPosition.inMicroseconds * 10;
      await reporter.reportStop(positionTicks: positionTicks);
    }

    // 上报 Trakt Scrobble 停止
    _reportTraktStop();

    // 停止播放器
    if (isUsingNativePlayer && _nativeBackend != null) {
      await _cleanupNativeBackend();
      // 重置后端类型
      state = state.copyWith(backendType: PlayerBackendType.mediaKit);
    } else {
      await _player.stop();
    }

    _currentVideo = null;
    _ref.read(currentVideoProvider.notifier).state = null;
  }

  /// 捕获当前帧作为进度截图
  Future<void> _captureProgressThumbnail() async {
    if (_currentVideo == null) return;
    // 只在播放进度 > 5% 且 < 95% 时保存进度截图
    if (state.progress <= 0.05 || state.progress >= 0.95) return;

    try {
      List<int>? screenshotData;

      if (isUsingNativePlayer && _nativeBackend != null) {
        // 原生播放器截图
        screenshotData = await _nativeBackend!.screenshot();
      } else {
        // media_kit 截图
        screenshotData = await _player.screenshot();
      }

      if (screenshotData != null && screenshotData.isNotEmpty) {
        await _thumbnailService.saveProgressThumbnail(
          videoPath: _currentVideo!.path,
          imageBytes: Uint8List.fromList(screenshotData),
        );
        logger.d('VideoPlayerNotifier: 进度截图已保存');
      }
    } on Exception catch (e, st) {
      // 截图失败不影响正常流程
      AppError.ignore(e, st, '进度截图捕获失败（非关键错误）');
    }
  }

  /// 同步停止（用于 dispose，不等待异步操作）
  void stopSync() {
    // 标记为已停止，防止 stream listeners 继续更新状态
    _isDisposed = true;

    // 取消所有 stream subscriptions
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();

    // 取消原生播放器订阅
    for (final subscription in _nativeSubscriptions) {
      subscription.cancel();
    }
    _nativeSubscriptions.clear();

    _stopProgressSaveTimer();

    // 保存当前视频和状态的引用，用于异步保存进度
    final videoToSave = _currentVideo;
    final positionToSave = state.position;
    final durationToSave = state.duration;

    // 停止播放器
    if (isUsingNativePlayer && _nativeBackend != null) {
      // 异步清理原生后端
      AppError.fireAndForget(_cleanupNativeBackend(), action: 'stopSyncNativeCleanup');
    } else {
      _player..pause()
      ..stop();
    }
    _currentVideo = null;

    // 延迟修改 provider 状态，避免在 dispose 期间修改
    Future.microtask(() {
      try {
        _ref.read(currentVideoProvider.notifier).state = null;
      } on Exception catch (e, st) {
        // Provider 可能已被销毁，这是预期行为
        AppError.ignore(e, st, 'Provider已销毁，无法修改状态');
      }
    });

    // 异步保存进度（使用保存的引用）
    if (videoToSave != null &&
        positionToSave.inSeconds >= 5 &&
        durationToSave.inSeconds >= 10) {
      logger.d('VideoPlayerNotifier: 异步保存进度 ${videoToSave.path} => ${positionToSave.inSeconds}s / ${durationToSave.inSeconds}s');
      Future.microtask(() async {
        try {
          await _historyService.saveProgress(
            videoPath: videoToSave.path,
            position: positionToSave,
            duration: durationToSave,
          );
          logger.i('VideoPlayerNotifier: 进度保存成功');
        } on Exception catch (e, st) {
          AppError.handle(e, st, 'VideoPlayer.saveProgress');
        }
      });
    }

    logger.i('VideoPlayerNotifier: 同步停止播放');
  }

  /// 跳转到指定位置
  Future<void> seek(Duration position) async {
    if (isUsingNativePlayer && _nativeBackend != null) {
      await _nativeBackend!.seek(position);
    } else {
      await _player.seek(position);
    }
  }

  /// 快进
  Future<void> seekForward({Duration? amount}) async {
    final settings = _ref.read(playbackSettingsProvider);
    final seekAmount = amount ?? Duration(seconds: settings.seekInterval);
    final newPosition = state.position + seekAmount;
    if (newPosition < state.duration) {
      await seek(newPosition);
    } else {
      await seek(state.duration);
    }
  }

  /// 快退
  Future<void> seekBackward({Duration? amount}) async {
    final settings = _ref.read(playbackSettingsProvider);
    final seekAmount = amount ?? Duration(seconds: settings.seekInterval);
    final newPosition = state.position - seekAmount;
    if (newPosition > Duration.zero) {
      await seek(newPosition);
    } else {
      await seek(Duration.zero);
    }
  }

  /// 设置音量 (0.0 - 1.0)
  Future<void> setVolume(double volume) async {
    if (isUsingNativePlayer && _nativeBackend != null) {
      await _nativeBackend!.setVolume(volume);
    } else {
      await _player.setVolume(volume * 100);
    }
    // 保存音量设置
    await _ref.read(playbackSettingsProvider.notifier).setVolume(volume);
  }

  /// 设置播放速度
  Future<void> setSpeed(double speed) async {
    if (isUsingNativePlayer && _nativeBackend != null) {
      await _nativeBackend!.setSpeed(speed);
    } else {
      await _player.setRate(speed);
    }
    // 保存速度设置
    await _ref.read(playbackSettingsProvider.notifier).setSpeed(speed);
  }

  /// 切换全屏
  void toggleFullscreen() {
    state = state.copyWith(isFullscreen: !state.isFullscreen);
  }

  /// 设置全屏状态
  void setFullscreen({required bool fullscreen}) {
    state = state.copyWith(isFullscreen: fullscreen);
  }

  /// 切换画中画模式
  Future<bool> togglePictureInPicture() async {
    final success = await _pipService.togglePipMode(
      aspectRatio: _calculateAspectRatio(),
    );
    if (success) {
      state = state.copyWith(isPictureInPicture: _pipService.isPipMode);
      // 进入画中画时退出全屏
      if (_pipService.isPipMode && state.isFullscreen) {
        state = state.copyWith(isFullscreen: false);
      }
    }
    return success;
  }

  /// 进入画中画模式
  Future<bool> enterPictureInPicture() async {
    final success = await _pipService.enterPipMode(
      aspectRatio: _calculateAspectRatio(),
    );
    if (success) {
      state = state.copyWith(isPictureInPicture: true, isFullscreen: false);
    }
    return success;
  }

  /// 退出画中画模式
  Future<bool> exitPictureInPicture() async {
    final success = await _pipService.exitPipMode();
    if (success) {
      state = state.copyWith(isPictureInPicture: false);
    }
    return success;
  }

  /// 计算视频宽高比
  double _calculateAspectRatio() {
    final width = _player.state.width;
    final height = _player.state.height;
    if (width != null && height != null && height > 0) {
      return width / height;
    }
    return 16 / 9; // 默认 16:9
  }

  /// 初始化画中画状态监听
  ///
  /// 由于 floating 包不提供状态流，我们通过轮询来检查状态变化
  void initPipStatusListener() {
    // floating 包没有提供实时的状态流
    // 画中画状态在 togglePictureInPicture 等方法中手动更新
    logger.d('VideoPlayerNotifier: 画中画状态监听已初始化');
  }

  /// 设置字幕
  Future<void> setSubtitle(SubtitleItem? subtitle) async {
    _ref.read(currentSubtitleProvider.notifier).state = subtitle;

    if (subtitle == null) {
      // 关闭字幕
      await _player.setSubtitleTrack(SubtitleTrack.no());
      logger.i('VideoPlayerNotifier: 关闭字幕');
    } else {
      // 加载外部字幕
      try {
        await _player.setSubtitleTrack(
          SubtitleTrack.uri(subtitle.url, title: subtitle.name),
        );
        logger.i('VideoPlayerNotifier: 加载字幕 ${subtitle.name}');
      } on Exception catch (e, st) {
        AppError.handle(e, st, 'VideoPlayer.loadSubtitle', {'name': subtitle.name});
      }
    }
  }

  /// 切换字幕显示
  void toggleSubtitle() {
    state = state.copyWith(subtitleEnabled: !state.subtitleEnabled);
    if (!state.subtitleEnabled) {
      _player.setSubtitleTrack(SubtitleTrack.no());
    } else {
      final current = _ref.read(currentSubtitleProvider);
      if (current != null) {
        _player.setSubtitleTrack(
          SubtitleTrack.uri(current.url, title: current.name),
        );
      }
    }
  }

  /// 获取内嵌字幕轨道
  List<SubtitleTrack> get embeddedSubtitles => _player.state.tracks.subtitle;

  /// 设置内嵌字幕轨道
  Future<void> setEmbeddedSubtitleTrack(SubtitleTrack track) async {
    await _player.setSubtitleTrack(track);
    logger.i('VideoPlayerNotifier: 设置内嵌字幕 ${track.title ?? track.id}');
  }

  /// 设置字幕延时（秒）
  ///
  /// [delay] 正值使字幕延后显示，负值使字幕提前显示
  ///
  /// 通过 media_kit NativePlayer 暴露的 [NativePlayer.setProperty] 直接写入
  /// MPV 的 `sub-delay` 属性。Web 平台不支持，仅记录日志后忽略。
  Future<void> setSubtitleDelay(double delay) async {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      try {
        await platform.setProperty('sub-delay', delay.toString());
        logger.i('VideoPlayerNotifier: 字幕延时已设置为 ${delay}s');
      } on Exception catch (e, st) {
        AppError.handle(e, st, 'videoPlayer.setSubtitleDelay', {'delay': delay});
      }
    } else {
      logger.d('VideoPlayerNotifier: 当前平台不支持设置字幕延时 ($platform)');
    }
  }

  /// 获取可用音轨列表
  List<AudioTrack> get audioTracks => _player.state.tracks.audio;

  /// 获取当前音轨
  AudioTrack? get currentAudioTrack => _player.state.track.audio;

  /// 设置音轨
  Future<void> setAudioTrack(AudioTrack track) async {
    await _player.setAudioTrack(track);
    logger.i('VideoPlayerNotifier: 设置音轨 ${track.title ?? track.id}');
  }

  /// 播放列表中的下一个
  Future<void> playNext() async {
    final nextVideo = _ref.read(playlistProvider.notifier).playNext();
    if (nextVideo != null) {
      await play(nextVideo);
    }
  }

  /// 播放列表中的上一个
  Future<void> playPrevious() async {
    final prevVideo = _ref.read(playlistProvider.notifier).playPrevious();
    if (prevVideo != null) {
      await play(prevVideo);
    }
  }

  /// 是否有下一个
  bool get hasNext => _ref.read(playlistProvider).hasNext;

  /// 是否有上一个
  bool get hasPrevious => _ref.read(playlistProvider).hasPrevious;

  @override
  void dispose() {
    _isDisposed = true;
    // 取消所有 stream subscriptions
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();

    // 取消原生播放器订阅
    for (final subscription in _nativeSubscriptions) {
      subscription.cancel();
    }
    _nativeSubscriptions.clear();

    // 停止转码并清理画质状态
    try {
      final qualityNotifier = _ref.read(qualityStateProvider.notifier);
      qualityNotifier.stopTranscoding();
    } catch (e) {
      // 忽略错误，可能 provider 已被销毁
    }

    // 退出画中画模式
    if (_pipService.isPipMode) {
      _pipService.exitPipMode();
    }

    _saveCurrentProgress();
    _stopProgressSaveTimer();

    // 清理原生后端
    if (_nativeBackend != null) {
      _nativeBackend!.dispose();
      _nativeBackend = null;
    }

    _player.dispose();
    super.dispose();
  }
}

/// 可用的播放速度
const availableSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
