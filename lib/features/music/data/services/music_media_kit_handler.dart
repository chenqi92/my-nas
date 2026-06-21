import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:media_kit/media_kit.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/audio_effects_service.dart';
import 'package:my_nas/features/music/data/services/music_audio_handler_interface.dart';
import 'package:my_nas/features/music/data/services/music_browser_service.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/video/domain/entities/audio_capability.dart';
import 'package:path_provider/path_provider.dart';

/// 基于 media_kit 的音乐播放 AudioHandler
///
/// 功能：
/// - 使用 media_kit Player 解码播放（支持 AC3/DTS/TrueHD 等所有格式）
/// - 集成 audio_service 实现系统媒体控制（锁屏、控制中心、蓝牙耳机）
/// - 支持音频直通模式（HDMI/eARC 场景）
///
/// 与 MusicAudioHandler (just_audio) 的主要区别：
/// - 使用 media_kit Player 替代 just_audio AudioPlayer
/// - 支持更多音频格式（AC3, DTS, TrueHD, Atmos 等）
/// - 支持音频直通配置
class MusicMediaKitAudioHandler extends BaseAudioHandler
    with SeekHandler, WidgetsBindingObserver
    implements IMusicAudioHandler {
  MusicMediaKitAudioHandler();

  // ==================== 私有字段 ====================

  /// media_kit 播放器实例
  late final Player _player;

  /// 是否已初始化
  bool _isInitialized = false;

  /// 是否已销毁
  bool _isDisposed = false;

  /// Stream 订阅列表（用于清理）
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  /// 当前封面数据
  Uint8List? _currentArtworkData;

  /// 当前音乐项
  MusicItem? _currentMusicItem;

  /// 播放队列
  final List<MusicItem> _musicQueue = [];

  /// 当前队列索引
  int _currentIndex = 0;

  /// 封面文件缓存目录
  Directory? _artworkCacheDir;

  /// 刷新计数器（用于灵动岛刷新）
  int _refreshCounter = 0;

  /// 当前音量 (0.0 - 1.0)
  double _volume = 1.0;

  // ==================== 音频直通配置 ====================

  /// 是否启用音频直通
  bool _passthroughEnabled = false;

  /// 启用的直通编码
  List<AudioCodec> _passthroughCodecs = [];

  // ==================== 公开属性 ====================

  /// 获取 media_kit Player 实例
  Player get player => _player;

  /// 当前封面数据
  @override
  Uint8List? get currentArtworkData => _currentArtworkData;

  /// 当前音乐项
  @override
  MusicItem? get currentMusicItem => _currentMusicItem;

  /// 当前索引
  @override
  int get currentIndex => _currentIndex;

  /// 外部切歌回调（用于处理复杂的音频源加载）
  @override
  Future<void> Function(int index)? onSkipToIndex;

  // ==================== Stream 访问器 ====================

  /// 播放位置流
  @override
  Stream<Duration> get positionStream => _player.stream.position;

  /// 缓冲位置流
  @override
  Stream<Duration> get bufferedPositionStream => _player.stream.buffer;

  /// 时长流
  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  /// 播放状态流
  @override
  Stream<bool> get playingStream => _player.stream.playing;

  /// 缓冲状态流
  @override
  Stream<bool> get bufferingStream => _player.stream.buffering;

  /// 播放完成流
  @override
  Stream<bool> get completedStream => _player.stream.completed;

  // ==================== 初始化与销毁 ====================

  /// 初始化播放器
  ///
  /// 必须在使用前调用
  Future<void> init() async {
    if (_isInitialized) {
      logger.w('MusicMediaKitHandler: 已经初始化，跳过');
      return;
    }

    logger.i('MusicMediaKitHandler: 开始初始化...');

    // 创建 media_kit Player
    _player = Player(
      configuration: const PlayerConfiguration(
        // 仅音频播放，不需要视频输出
        // 使用默认配置，后续根据直通设置调整
      ),
    );

    // 配置 MPV 播放器选项（禁用自动字幕加载等）
    await _configureMpvOptions();

    // 初始化封面缓存目录
    await _initArtworkCacheDir();

    // 注册生命周期监听器
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addObserver(this);
      logger.d('MusicMediaKitHandler: 生命周期监听器已注册');
    });

    // 设置 Stream 监听
    _setupStreamListeners();

    // 接入均衡器：初始应用一次 + 订阅后续变化
    await _initEqualizer();

    // 广播初始状态
    _broadcastPlaybackState();

    _isInitialized = true;
    logger.i('MusicMediaKitHandler: 初始化完成');
  }

  // ============ MediaBrowserService（Android Auto / CarPlay）============

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) =>
      MusicBrowserService.instance.getChildren(parentMediaId);

  @override
  Future<MediaItem?> getMediaItem(String mediaId) =>
      MusicBrowserService.instance.getMediaItem(mediaId);

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) =>
      MusicBrowserService.instance.playFromMediaId(mediaId);

  @override
  Future<void> playFromSearch(
    String query, [
    Map<String, dynamic>? extras,
  ]) =>
      MusicBrowserService.instance.playFromSearch(query);

  @override
  Future<List<MediaItem>> search(
    String query, [
    Map<String, dynamic>? extras,
  ]) =>
      MusicBrowserService.instance.search(query);

  /// 初始化均衡器并订阅状态变化
  Future<void> _initEqualizer() async {
    await AudioEffectsService.instance.init();
    await _applyEqualizer(AudioEffectsService.instance.state);
    _subscriptions.add(
      AudioEffectsService.instance.onChange.listen((state) {
        if (_isDisposed) return;
        AppError.fireAndForget(
          _applyEqualizer(state),
          action: 'mediaKit.applyEqualizer',
        );
      }),
    );
  }

  /// 把均衡器状态写到 mpv `af` 滤镜
  Future<void> _applyEqualizer(EqualizerState state) async {
    final nativePlayer = _player.platform;
    if (nativePlayer is! NativePlayer) return;
    final filter = buildMpvEqualizerFilter(state);
    try {
      // 空字符串 → 关闭 af；否则下发滤镜链
      await nativePlayer.setProperty('af', filter);
      logger.d('MusicMediaKitHandler: af="$filter"');
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'mediaKit.setAf', {'filter': filter});
    }
  }

  /// 设置 Stream 监听器
  void _setupStreamListeners() {
    // 监听播放状态
    _subscriptions
      ..add(_player.stream.playing.listen((playing) {
        if (_isDisposed) return;
        _broadcastPlaybackState();
      }))

      // 监听缓冲状态
      ..add(_player.stream.buffering.listen((buffering) {
        if (_isDisposed) return;
        _broadcastPlaybackState();
      }))

      // 监听位置变化
      ..add(_player.stream.position.listen((position) {
        if (_isDisposed) return;
        // audio_service 会自动根据 playbackState.updatePosition 计算位置
        // 只在特定情况下更新（如 seek 后）
      }))

      // 监听时长变化
      ..add(_player.stream.duration.listen((duration) {
        if (_isDisposed) return;
        if (duration > Duration.zero && mediaItem.value != null) {
          mediaItem.add(mediaItem.value!.copyWith(duration: duration));
        }
      }))

      // 监听播放完成
      ..add(_player.stream.completed.listen((completed) {
        if (_isDisposed) return;
        if (completed) {
          logger.i('MusicMediaKitHandler: 播放完成');
          _broadcastPlaybackState();
        }
      }))

      // 监听错误
      ..add(_player.stream.error.listen((error) {
        if (_isDisposed) return;
        if (error.isNotEmpty) {
          logger.e('MusicMediaKitHandler: 播放错误 - $error');
        }
      }));

    logger.d('MusicMediaKitHandler: Stream 监听器已设置');
  }

  /// 初始化封面缓存目录
  Future<void> _initArtworkCacheDir() async {
    try {
      final tempDir = await getTemporaryDirectory();
      _artworkCacheDir = Directory('${tempDir.path}/now_playing_artwork_mk');
      if (!await _artworkCacheDir!.exists()) {
        await _artworkCacheDir!.create(recursive: true);
      }
      logger.d('MusicMediaKitHandler: 封面缓存目录已初始化: ${_artworkCacheDir!.path}');
    } on Exception catch (e) {
      logger.e('MusicMediaKitHandler: 初始化封面缓存目录失败: $e');
    }
  }

  /// 释放资源
  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    logger.i('MusicMediaKitHandler: 开始释放资源...');

    // 移除生命周期监听器
    WidgetsBinding.instance.removeObserver(this);

    // 取消所有 Stream 订阅
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    // 释放播放器
    await _player.dispose();

    logger.i('MusicMediaKitHandler: 资源已释放');
  }

  // ==================== 播放状态广播 ====================

  /// 广播播放状态到 audio_service
  void _broadcastPlaybackState() {
    final playing = _player.state.playing;
    final buffering = _player.state.buffering;
    final position = _player.state.position;
    final duration = _player.state.duration;

    // 映射处理状态
    AudioProcessingState processingState;
    if (buffering) {
      processingState = AudioProcessingState.buffering;
    } else if (_player.state.completed) {
      processingState = AudioProcessingState.completed;
    } else if (duration > Duration.zero) {
      processingState = AudioProcessingState.ready;
    } else {
      processingState = AudioProcessingState.idle;
    }

    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: processingState,
      playing: playing,
      updatePosition: position,
      bufferedPosition: _player.state.buffer,
      speed: _player.state.rate,
      queueIndex: _currentIndex,
    ));
  }

  // ==================== BaseAudioHandler 实现 ====================

  @override
  Future<void> play() async {
    logger.i('MusicMediaKitHandler: play()');
    await _player.play();
    // 短暂等待确保状态更新
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _broadcastPlaybackState();
  }

  @override
  Future<void> pause() async {
    logger.i('MusicMediaKitHandler: pause()');
    await _player.pause();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _broadcastPlaybackState();
  }

  @override
  Future<void> stop() async {
    logger.i('MusicMediaKitHandler: stop()');
    await _player.stop();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _broadcastPlaybackState();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    logger.d('MusicMediaKitHandler: seek($position)');
    await _player.seek(position);
    _broadcastPlaybackState();
  }

  @override
  Future<void> skipToNext() async {
    logger.i('MusicMediaKitHandler: skipToNext()');
    if (_musicQueue.isEmpty) {
      logger.w('MusicMediaKitHandler: 队列为空，忽略');
      return;
    }

    final nextIndex = (_currentIndex + 1) % _musicQueue.length;
    await _skipToIndex(nextIndex);
  }

  @override
  Future<void> skipToPrevious() async {
    logger.i('MusicMediaKitHandler: skipToPrevious()');
    if (_musicQueue.isEmpty) {
      logger.w('MusicMediaKitHandler: 队列为空，忽略');
      return;
    }

    // 如果播放超过3秒，回到开头
    if (_player.state.position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }

    final prevIndex = (_currentIndex - 1 + _musicQueue.length) % _musicQueue.length;
    await _skipToIndex(prevIndex);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    logger.d('MusicMediaKitHandler: skipToQueueItem($index)');
    await _skipToIndex(index);
  }

  /// 内部跳转到指定索引
  Future<void> _skipToIndex(int index) async {
    if (index < 0 || index >= _musicQueue.length) {
      logger.w('MusicMediaKitHandler: 索引超出范围 [$index]');
      return;
    }

    _currentIndex = index;

    // 调用外部回调处理音频源加载
    if (onSkipToIndex != null) {
      await onSkipToIndex!(index);
    }
  }

  @override
  Future<void> setSpeed(double speed) async {
    logger.d('MusicMediaKitHandler: setSpeed($speed)');
    await _player.setRate(speed);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    // 由 MusicPlayerNotifier 处理
    logger.d('MusicMediaKitHandler: setRepeatMode($repeatMode) - 由 Notifier 处理');
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    // 由 MusicPlayerNotifier 处理
    logger.d('MusicMediaKitHandler: setShuffleMode($shuffleMode) - 由 Notifier 处理');
  }

  // ==================== 音频控制 ====================

  /// 设置音量 (0.0 - 1.0)
  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    // media_kit 音量范围是 0-100
    await _player.setVolume(_volume * 100);
    logger.d('MusicMediaKitHandler: setVolume($_volume)');
  }

  /// 获取当前音量
  @override
  double get volume => _volume;

  /// 准备切换到新歌曲
  @override
  Future<void> prepareForNewTrack() async {
    logger.i('MusicMediaKitHandler: prepareForNewTrack()');

    // 如果正在播放，先暂停
    if (_player.state.playing) {
      await _player.pause();
      _broadcastPlaybackState();
    }

    // 清理当前音乐信息
    _currentMusicItem = null;
    _currentArtworkData = null;
  }

  // ==================== 音频源设置 ====================

  /// 设置音频源
  ///
  /// [url] 音频文件 URL（支持 file://, http://, https://）
  /// [headers] HTTP 请求头（可选）
  @override
  Future<Duration?> setAudioSource(String url, {Map<String, String>? headers}) async {
    logger.i('MusicMediaKitHandler: setAudioSource($url)');

    try {
      // 创建 Media 对象
      Media media;
      if (headers != null && headers.isNotEmpty) {
        media = Media(url, httpHeaders: headers);
      } else {
        media = Media(url);
      }

      // 打开媒体
      await _player.open(media, play: false);

      // 等待时长加载
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final duration = _player.state.duration;
      logger.i('MusicMediaKitHandler: 音频源设置成功，时长=$duration');

      return duration;
    } on Exception catch (e, st) {
      logger.e('MusicMediaKitHandler: 设置音频源失败', e, st);
      rethrow;
    }
  }

  /// 停止播放器
  @override
  Future<void> stopPlayer() async {
    logger.d('MusicMediaKitHandler: stopPlayer()');
    await _player.stop();
  }

  /// 跳转到指定位置
  @override
  Future<void> seekTo(Duration position) async {
    logger.d('MusicMediaKitHandler: seekTo($position)');
    await _player.seek(position);
  }

  /// 设置当前播放的音乐
  @override
  Future<void> setCurrentMusic(MusicItem music, {Uint8List? artworkData}) async {
    logger.i('MusicMediaKitHandler: setCurrentMusic(${music.displayTitle})');

    _currentMusicItem = music;
    _currentArtworkData = artworkData;

    // 处理封面图片
    Uri? artUri;
    if (artworkData != null && artworkData.isNotEmpty) {
      artUri = await _saveArtworkToFile(artworkData, music.id);
    }

    // 创建 MediaItem 用于 Now Playing 显示
    final item = MediaItem(
      id: music.id,
      title: music.displayTitle,
      artist: music.displayArtist,
      album: music.displayAlbum,
      duration: music.duration ?? Duration.zero,
      artUri: artUri,
      extras: {
        'sourceId': music.sourceId,
        'path': music.path,
      },
    );

    mediaItem.add(item);
    _broadcastPlaybackState();

    logger.i('MusicMediaKitHandler: MediaItem 已设置 - ${music.displayTitle}');
  }

  /// 更新封面图片
  @override
  Future<void> updateArtwork(Uint8List artworkData) async {
    _currentArtworkData = artworkData;

    if (mediaItem.value != null) {
      final artUri = await _saveArtworkToFile(artworkData, mediaItem.value!.id);

      final updated = mediaItem.value!.copyWith(artUri: artUri);
      mediaItem.add(updated);
      _broadcastPlaybackState();

      logger.i('MusicMediaKitHandler: 封面已更新');
    }
  }

  /// 更新时长
  @override
  void updateDuration(Duration duration) {
    if (mediaItem.value != null && duration > Duration.zero) {
      mediaItem.add(mediaItem.value!.copyWith(duration: duration));
    }
  }

  // ==================== 播放队列 ====================

  /// 设置播放队列
  @override
  void setQueue(List<MusicItem> items, {int startIndex = 0}) {
    _musicQueue
      ..clear()
      ..addAll(items);
    _currentIndex = startIndex;

    // 转换为 MediaItem 列表并更新 queue
    final mediaItems = items
        .map((m) => MediaItem(
              id: m.id,
              title: m.displayTitle,
              artist: m.displayArtist,
              album: m.displayAlbum,
              duration: m.duration,
            ))
        .toList();
    queue.add(mediaItems);

    logger.d('MusicMediaKitHandler: 设置队列 ${items.length} 首歌');
  }

  /// 更新当前索引
  @override
  void updateCurrentIndex(int index) {
    _currentIndex = index;
    _broadcastPlaybackState();
  }

  // ==================== 音频直通配置 ====================

  /// 设置音频直通模式
  ///
  /// [enabled] 是否启用直通
  /// [codecs] 启用的直通编码（null 表示全部支持的编码）
  Future<void> setPassthroughEnabled({
    required bool enabled,
    List<AudioCodec>? codecs,
  }) async {
    _passthroughEnabled = enabled;
    _passthroughCodecs = codecs ?? [];

    await _applyPassthroughConfig();
  }

  /// 配置 MPV 播放器选项
  Future<void> _configureMpvOptions() async {
    try {
      final nativePlayer = _player.platform;
      if (nativePlayer is NativePlayer) {
        // 禁用自动字幕/歌词加载 - 我们有自己的歌词服务
        await nativePlayer.setProperty('sub-auto', 'no');
        // 禁用 OSD 显示
        await nativePlayer.setProperty('osd-level', '0');
        logger.d('MusicMediaKitHandler: MPV 选项已配置');
      }
    } on Exception catch (e, st) {
      // 配置失败不影响播放，仅记录日志
      logger.w('MusicMediaKitHandler: 配置 MPV 选项失败', e, st);
    }
  }

  /// 应用直通配置
  Future<void> _applyPassthroughConfig() async {
    if (!_passthroughEnabled || _passthroughCodecs.isEmpty) {
      logger.d('MusicMediaKitHandler: 音频直通未启用');
      return;
    }

    try {
      final nativePlayer = _player.platform;
      if (nativePlayer is NativePlayer) {
        // 构建 SPDIF 编码列表
        final spdifCodecs = _passthroughCodecs.map((c) => c.mpvName).join(',');

        // 设置 MPV 属性
        await nativePlayer.setProperty('audio-spdif', spdifCodecs);
        await nativePlayer.setProperty('audio-channels', 'auto-safe');

        // Windows 独占模式
        if (Platform.isWindows) {
          await nativePlayer.setProperty('audio-exclusive', 'yes');
        }

        logger.i('MusicMediaKitHandler: 音频直通已启用 - $spdifCodecs');
      }
    } on Exception catch (e, st) {
      logger.e('MusicMediaKitHandler: 应用直通配置失败', e, st);
    }
  }

  /// 获取直通配置
  ({bool enabled, List<AudioCodec> codecs}) get passthroughConfig => (
        enabled: _passthroughEnabled,
        codecs: _passthroughCodecs,
      );

  // ==================== 封面处理 ====================

  /// iOS Now Playing 的最大封面尺寸
  static const int _maxArtworkSize = 600;

  /// 保存封面到文件并返回文件 URI
  Future<Uri?> _saveArtworkToFile(Uint8List artworkData, String musicId) async {
    if (_artworkCacheDir == null) {
      await _initArtworkCacheDir();
    }
    if (_artworkCacheDir == null) return null;

    try {
      final safeId = musicId.replaceAll(RegExp(r'[^\w\-]'), '_');
      final filePath = '${_artworkCacheDir!.path}/$safeId.jpg';
      final file = File(filePath);

      // 检查缓存
      final hashPath = '${_artworkCacheDir!.path}/$safeId.hash';
      final hashFile = File(hashPath);
      final currentHash = artworkData.length.toString();
      String? existingHash;
      if (await hashFile.exists()) {
        existingHash = await hashFile.readAsString();
      }

      if (await file.exists() && existingHash == currentHash) {
        return Uri.file(filePath);
      }

      // 解码和调整大小
      final originalImage = img.decodeImage(artworkData);
      if (originalImage == null) return null;

      img.Image processedImage;
      if (originalImage.width > _maxArtworkSize || originalImage.height > _maxArtworkSize) {
        if (originalImage.width > originalImage.height) {
          processedImage = img.copyResize(originalImage, width: _maxArtworkSize);
        } else {
          processedImage = img.copyResize(originalImage, height: _maxArtworkSize);
        }
      } else {
        processedImage = originalImage;
      }

      // 保存 JPEG
      final jpegData = img.encodeJpg(processedImage, quality: 85);
      await file.writeAsBytes(jpegData);
      await hashFile.writeAsString(currentHash);

      return Uri.file(filePath);
    } on Exception catch (e, st) {
      logger.e('MusicMediaKitHandler: 保存封面失败', e, st);
      return null;
    }
  }

  // ==================== 生命周期管理 ====================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    logger.d('MusicMediaKitHandler: 生命周期变化 - $state');

    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // 进入后台，由原生层处理灵动岛
        break;

      case AppLifecycleState.paused:
        // 已进入后台
        break;

      case AppLifecycleState.resumed:
        // 返回前台，重新激活音频会话
        if (_player.state.playing && Platform.isIOS) {
          AppError.fireAndForget(
            _reactivateAudioSession(),
            action: 'mediaKitHandler.reactivateAudioSession',
          );
        }

      case AppLifecycleState.detached:
        // App 正在分离，无需处理
    }
  }

  /// 重新激活音频会话
  Future<void> _reactivateAudioSession() async {
    try {
      final session = await AudioSession.instance;
      final success = await session.setActive(true);
      logger.d('MusicMediaKitHandler: 重新激活 AudioSession, success=$success');

      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (_player.state.playing && mediaItem.value != null) {
        _broadcastPlaybackState();
      }
    } on Exception catch (e) {
      logger.w('MusicMediaKitHandler: 重新激活 AudioSession 失败: $e');
    }
  }

  /// 强制刷新 Now Playing / 灵动岛
  @override
  Future<void> refreshNowPlaying() async {
    final currentItem = mediaItem.value;
    if (currentItem == null) return;

    _refreshCounter++;

    Uri? newArtUri;
    if (_currentArtworkData != null && _currentArtworkData!.isNotEmpty) {
      final timestampedId = '${currentItem.id}_refresh_$_refreshCounter';
      newArtUri = await _saveArtworkToFile(_currentArtworkData!, timestampedId);
    } else {
      newArtUri = currentItem.artUri;
    }

    final refreshedItem = MediaItem(
      id: currentItem.id,
      title: currentItem.title,
      artist: currentItem.artist,
      album: currentItem.album,
      duration: _player.state.duration,
      artUri: newArtUri,
      extras: currentItem.extras,
    );

    mediaItem.add(refreshedItem);
    _broadcastPlaybackState();

    logger.d('MusicMediaKitHandler: Now Playing 已刷新');
  }
}

/// 全局 AudioHandler 初始化（media_kit 版本）
Future<MusicMediaKitAudioHandler> initMediaKitAudioHandler() async {
  final handler = await AudioService.init<MusicMediaKitAudioHandler>(
    builder: () {
      final h = MusicMediaKitAudioHandler();
      // init() 需要在返回后调用
      return h;
    },
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.kkape.mynas.channel.audio',
      androidNotificationChannelName: appL10n.musicNotificationChannelName,
      androidNotificationChannelDescription: appL10n.musicNotificationChannelDescription,
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      fastForwardInterval: Duration(seconds: 10),
      rewindInterval: Duration(seconds: 10),
      preloadArtwork: true,
      androidNotificationClickStartsActivity: true,
    ),
  );

  // 初始化播放器
  await handler.init();

  return handler;
}
