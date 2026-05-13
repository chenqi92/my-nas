import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/services/media_proxy_server.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/android_dynamic_island_service.dart';
import 'package:my_nas/features/music/data/services/ffmpeg_audio_tag_service.dart';
import 'package:my_nas/features/music/data/services/music_audio_cache_service.dart';
import 'package:my_nas/features/music/data/services/music_audio_handler.dart';
import 'package:my_nas/features/music/data/services/music_audio_handler_interface.dart';
import 'package:my_nas/features/music/data/services/music_browser_service.dart';
import 'package:my_nas/features/music/data/services/music_cover_cache_service.dart';
import 'package:my_nas/features/music/data/services/music_favorites_service.dart';
import 'package:my_nas/features/music/data/services/music_metadata_service.dart';
import 'package:my_nas/features/music/data/services/ncm_decrypt_service.dart';
import 'package:my_nas/features/music/data/services/play_history_store.dart';
import 'package:my_nas/features/music/data/services/scrobble/music_scrobble_service.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/presentation/providers/music_favorites_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_settings_provider.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/main.dart' show audioHandler;
import 'package:my_nas/shared/models/widget_data_models.dart';
import 'package:my_nas/shared/services/widget_data_service.dart';
import 'package:path/path.dart' as p;

/// 当前播放的音乐
final currentMusicProvider = StateProvider<MusicItem?>((ref) => null);

/// 播放队列
final playQueueProvider =
    StateNotifierProvider<PlayQueueNotifier, List<MusicItem>>((ref) =>
        PlayQueueNotifier());

/// 音乐播放器控制器
final musicPlayerControllerProvider =
    StateNotifierProvider<MusicPlayerNotifier, MusicPlayerState>(MusicPlayerNotifier.new);

/// 播放模式
enum PlayMode {
  /// 列表循环
  loop,

  /// 单曲循环
  repeatOne,

  /// 随机播放
  shuffle,
}

/// FLAC 文件已修复，需要重试播放的异常
/// 用于内部通知 play() 方法重新尝试
 class FlacRepairedNeedRetryException implements Exception {
  FlacRepairedNeedRetryException(this.music);
  final MusicItem music;

  @override
  String toString() => 'FlacRepairedNeedRetryException: FLAC 文件已修复，需要重试播放';
}

/// 播放器状态
class MusicPlayerState {
  const MusicPlayerState({
    this.isPlaying = false,
    this.isBuffering = false,
    this.position = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 1.0,
    this.playMode = PlayMode.loop,
    this.currentIndex = 0,
    this.errorMessage,
  });

  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;
  final double volume;
  final PlayMode playMode;
  final int currentIndex;
  final String? errorMessage;

  double get progress =>
      duration.inMilliseconds > 0 ? position.inMilliseconds / duration.inMilliseconds : 0;

  /// 缓冲进度 (0.0 - 1.0)
  double get bufferedProgress =>
      duration.inMilliseconds > 0 ? bufferedPosition.inMilliseconds / duration.inMilliseconds : 0;

  String get positionText => _formatDuration(position);
  String get durationText => _formatDuration(duration);

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  MusicPlayerState copyWith({
    bool? isPlaying,
    bool? isBuffering,
    Duration? position,
    Duration? bufferedPosition,
    Duration? duration,
    double? volume,
    PlayMode? playMode,
    int? currentIndex,
    String? errorMessage,
  }) =>
      MusicPlayerState(
        isPlaying: isPlaying ?? this.isPlaying,
        isBuffering: isBuffering ?? this.isBuffering,
        position: position ?? this.position,
        bufferedPosition: bufferedPosition ?? this.bufferedPosition,
        duration: duration ?? this.duration,
        volume: volume ?? this.volume,
        playMode: playMode ?? this.playMode,
        currentIndex: currentIndex ?? this.currentIndex,
        errorMessage: errorMessage,
      );
}

/// 播放队列管理
class PlayQueueNotifier extends StateNotifier<List<MusicItem>> {
  PlayQueueNotifier() : super([]);

  void setQueue(List<MusicItem> tracks) {
    state = tracks;
  }

  void addToQueue(MusicItem track) {
    state = [...state, track];
  }

  /// 添加到下一首播放（在指定索引后插入）
  void addNext(MusicItem track, int currentIndex) {
    if (state.isEmpty) {
      state = [track];
    } else {
      final insertIndex = (currentIndex + 1).clamp(0, state.length);
      final newList = [...state]..insert(insertIndex, track);
      state = newList;
    }
  }

  void removeFromQueue(int index) {
    if (index >= 0 && index < state.length) {
      final newList = [...state]
      ..removeAt(index);
      state = newList;
    }
  }

  void clear() {
    state = [];
  }

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.length) return;
    if (newIndex < 0 || newIndex >= state.length) return;

    final newList = [...state];
    final item = newList.removeAt(oldIndex);
    newList.insert(newIndex, item);
    state = newList;
  }

  /// 更新队列中指定歌曲的封面
  void updateTrackCover(String musicId, {List<int>? coverData, String? coverUrl}) {
    final newList = state.map((track) {
      if (track.id == musicId) {
        return track.copyWith(
          coverData: coverData,
          coverUrl: coverUrl,
        );
      }
      return track;
    }).toList();
    state = newList;
  }

  /// 更新队列中指定歌曲的元数据（仅补充缺失的字段）
  void updateTrackMetadata(
    String musicId, {
    String? title,
    String? artist,
    String? album,
    int? year,
    int? trackNumber,
    String? genre,
  }) {
    final newList = state.map((track) {
      if (track.id == musicId) {
        return track.copyWith(
          // 只补充缺失的字段
          title: (track.title == null || track.title!.isEmpty) ? title : track.title,
          artist: (track.artist == null || track.artist!.isEmpty) ? artist : track.artist,
          album: (track.album == null || track.album!.isEmpty) ? album : track.album,
          year: track.year ?? year,
          trackNumber: track.trackNumber ?? trackNumber,
          genre: (track.genre == null || track.genre!.isEmpty) ? genre : track.genre,
        );
      }
      return track;
    }).toList();
    state = newList;
  }
}

/// 音乐播放器管理
/// 使用 audio_service 实现后台音频播放和系统媒体控制（锁屏、控制中心、蓝牙耳机）
class MusicPlayerNotifier extends StateNotifier<MusicPlayerState> {
  MusicPlayerNotifier(this._ref) : super(const MusicPlayerState()) {
    _initPlayer();
    _initMediaProxy();
  }

  final Ref _ref;

  /// 使用全局 AudioHandler（通过 audio_service 初始化）
  /// 这提供了后台音频播放和系统媒体控制（锁屏、控制中心、蓝牙耳机）
  IMusicAudioHandler get _audioHandler => audioHandler;

  /// 判断是否使用 just_audio 引擎
  bool get _isJustAudioEngine => audioHandler is MusicAudioHandler;

  /// 获取底层的 AudioPlayer（仅 just_audio 引擎可用）
  /// 注意：media_kit 引擎需要不同的访问方式
  AudioPlayer get _player {
    if (audioHandler is MusicAudioHandler) {
      return (audioHandler as MusicAudioHandler).player;
    }
    throw UnsupportedError('当前播放引擎不支持直接访问 AudioPlayer');
  }

  // 媒体代理服务器（用于流式播放 NAS 文件）
  final MediaProxyServer _mediaProxyServer = MediaProxyServer();

  // 当前代理的文件 ID（用于清理）
  String? _currentProxyId;

  // 音频缓存服务（用于持久化缓存，避免重复下载）
  final MusicAudioCacheService _audioCacheService = MusicAudioCacheService();

  // 防止并发播放的标志
  // 当 play() 正在执行时，新的 play() 调用会等待或取消
  bool _isPlayOperationInProgress = false;

  // 随机数生成器（用于随机播放模式）
  final math.Random _random = math.Random();

  // NCM 解密服务
  final NcmDecryptService _ncmDecryptService = NcmDecryptService();

  // 淡入淡出相关
  bool _isFadingOut = false;
  bool _isFadingIn = false;
  double _targetVolume = 1.0;

  // 交叉淡化相关
  AudioPlayer? _crossfadePlayer; // 用于交叉淡化的辅助播放器
  bool _isCrossfading = false;
  bool _isPreloading = false;
  MusicItem? _preloadedMusic; // 预加载的下一首歌曲

  // 播放状态持久化
  final MusicFavoritesService _favoritesService = MusicFavoritesService();
  DateTime? _lastStateSaveTime;
  static const _stateSaveInterval = Duration(seconds: 10);

  // Android 灵动岛服务
  final AndroidDynamicIslandService _dynamicIslandService = AndroidDynamicIslandService();
  bool _dynamicIslandEnabled = true; // 默认开启，不在 UI 上显示开关

  /// iOS 不支持的音频格式回调
  /// 当在 iOS 上使用 just_audio 引擎播放 FLAC 等不支持的格式时触发
  /// UI 层可以设置此回调来显示切换引擎的提示对话框
  void Function(String formatName)? onUnsupportedFormatDetected;

  /// iOS 上 just_audio 引擎（原生 AVFoundation）不支持的音频格式
  /// 这些格式需要使用 MediaKit（FFmpeg 解码器）才能播放
  ///
  /// 注意：FLAC 自 iOS 11 起已被 AVFoundation 原生支持，因此不在此列表中
  /// 参考：https://developer.apple.com/documentation/avfoundation/audio_track_engineering/audio_format_support
  static const _iosUnsupportedFormats = {
    '.ape',  // Monkey's Audio
    '.tta',  // True Audio
    '.wma',  // Windows Media Audio
    '.dsd',  // Direct Stream Digital
    '.dsf',  // DSD Stream File
    '.dff',  // DSD Interchange File Format
    '.mka',  // Matroska Audio
    // 以下格式在现代 iOS 上通常支持，但可能存在兼容性问题
    // '.ogg',  // Ogg Vorbis（iOS 部分支持）
    // '.opus', // Opus（iOS 14+ 支持）
  };

  /// 检查文件是否为 iOS 上 just_audio 引擎不支持的格式
  static bool isUnsupportedOnIosWithJustAudio(String filePath) {
    if (!Platform.isIOS) return false;
    final ext = p.extension(filePath).toLowerCase();
    return _iosUnsupportedFormats.contains(ext);
  }

  /// 获取格式的显示名称
  static String _getFormatDisplayName(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    return switch (ext) {
      '.flac' => 'FLAC',
      '.ape' => 'APE',
      '.tta' => 'TTA',
      '.wma' => 'WMA',
      '.dsd' || '.dsf' || '.dff' => 'DSD',
      '.mka' => 'MKA',
      '.ogg' => 'OGG',
      '.opus' => 'Opus',
      _ => ext.toUpperCase().substring(1),
    };
  }

  AudioPlayer get player => _player;

  /// 初始化媒体代理服务器
  Future<void> _initMediaProxy() async {
    await _mediaProxyServer.start();
  }

  void _initPlayer() {
    logger.i('MusicPlayer: 使用全局 AudioHandler (engine=${_isJustAudioEngine ? "just_audio" : "media_kit"})');

    // 设置 audioHandler 的切歌回调
    // 当用户通过锁屏、控制中心或蓝牙耳机点击上一首/下一首时调用
    _audioHandler.onSkipToIndex = (index) async {
      await playAt(index);
    };

    // 注册 Android Auto / CarPlay 浏览播放回调
    MusicBrowserService.instance.playFromPathsHandler =
        _playFromBrowserPaths;

    // 配置 AudioSession（关键：确保灵动岛/Now Playing 正常显示）
    _configureAudioSession();

    // 应用保存的设置
    _applySettings();

    // 初始化音频会话中断处理
    _initAudioSessionHandling();

    // 监听播放状态（使用接口提供的流，兼容两种引擎）
    _audioHandler.playingStream.listen((playing) {
      state = state.copyWith(isPlaying: playing);
      // 更新 Android 灵动岛播放状态
      AppError.fireAndForget(_updateDynamicIsland(), action: 'musicPlayer.updateDynamicIsland');
      // 更新 iOS/macOS 媒体小组件
      AppError.fireAndForget(_updateMediaWidget(), action: 'musicPlayer.updateMediaWidget');
    });

    // 监听缓冲状态（使用接口提供的流）
    _audioHandler.bufferingStream.listen((buffering) {
      state = state.copyWith(isBuffering: buffering);
    });

    // 监听播放完成（使用接口提供的流）
    // 使用 distinct 确保只有状态变化时才触发，避免重复触发
    _audioHandler.completedStream
        .distinct()
        .where((completed) => completed)
        .listen((_) {
      _onTrackCompleted();
    });

    // 监听播放位置（使用播放器原生的 positionStream，无需定时器）
    _audioHandler.positionStream.listen((position) {
      state = state.copyWith(position: position);
      // 检查是否需要开始淡出（歌曲快结束时）
      _checkFadeOut(position);
      // 定期保存播放状态（用于连接后自动恢复）
      _savePlayStateIfNeeded(position);
      // 听歌统计：维护 high-water mark
      PlayHistoryStore.instance.tick(position);
      // Scrobble：同步 high-water mark
      MusicScrobbleService.instance.tick(position);
    });

    // 监听总时长
    _audioHandler.durationStream.listen((duration) {
      if (duration > Duration.zero) {
        state = state.copyWith(duration: duration);
      }
    });

    // 监听缓冲位置（边下边播时显示已下载进度）
    _audioHandler.bufferedPositionStream.listen((bufferedPosition) {
      state = state.copyWith(bufferedPosition: bufferedPosition);
    });

    // 初始化 Android 灵动岛服务
    _initDynamicIsland();
  }

  /// 初始化 Android 灵动岛服务
  Future<void> _initDynamicIsland() async {
    if (!Platform.isAndroid) return;

    try {
      await _dynamicIslandService.init();

      // 从设置加载灵动岛开关状态（默认开启）
      final settings = _ref.read(musicSettingsProvider);
      _dynamicIslandEnabled = settings.dynamicIslandEnabled;

      // 设置控制回调
      _dynamicIslandService.onControlAction = (action) {
        logger.i('MusicPlayer: 收到灵动岛控制命令: $action');
        switch (action) {
          case 'playPause':
            playOrPause();
          case 'next':
            playNext();
          case 'previous':
            playPrevious();
          case 'dismiss':
            // 用户关闭了灵动岛，下次播放时会重新显示
            break;
          case _ when action.startsWith('seek:'):
            final position = int.tryParse(action.substring(5));
            if (position != null) {
              seek(Duration(milliseconds: position));
            }
        }
      };

      logger.i('MusicPlayer: Android 灵动岛服务初始化完成');
    } on Exception catch (e, st) {
      logger.e('MusicPlayer: Android 灵动岛服务初始化失败', e, st);
    }
  }

  /// 更新 Android 灵动岛状态
  Future<void> _updateDynamicIsland({
    MusicItem? music,
    Uint8List? coverData,
  }) async {
    if (!Platform.isAndroid || !_dynamicIslandEnabled) return;

    final currentMusic = music ?? _ref.read(currentMusicProvider);
    if (currentMusic == null) return;

    try {
      await _dynamicIslandService.updateActivity(
        music: currentMusic,
        isPlaying: state.isPlaying,
        position: state.position,
        duration: state.duration,
        coverData: coverData,
      );
    } on Exception catch (e, st) {
      logger.e('MusicPlayer: 更新灵动岛失败', e, st);
    }
  }

  /// 开始显示 Android 灵动岛
  Future<void> _startDynamicIsland({
    required MusicItem music,
    Uint8List? coverData,
  }) async {
    if (!Platform.isAndroid || !_dynamicIslandEnabled) return;

    try {
      await _dynamicIslandService.startMusicActivity(
        music: music,
        isPlaying: true,
        position: Duration.zero,
        duration: state.duration,
        coverData: coverData,
      );
    } on Exception catch (e, st) {
      logger.e('MusicPlayer: 启动灵动岛失败', e, st);
    }
  }

  /// 隐藏 Android 灵动岛
  Future<void> _hideDynamicIsland() async {
    if (!Platform.isAndroid) return;

    try {
      await _dynamicIslandService.endActivity();
    } on Exception catch (e, st) {
      logger.e('MusicPlayer: 隐藏灵动岛失败', e, st);
    }
  }

  /// 更新 iOS/macOS 媒体小组件
  Future<void> _updateMediaWidget() async {
    // 只在 iOS 和 macOS 上更新 Widget
    if (!Platform.isIOS && !Platform.isMacOS) return;

    final currentMusic = _ref.read(currentMusicProvider);

    if (currentMusic == null) {
      // 没有播放内容，清空 Widget
      await widgetDataService.clearMediaWidget();
      return;
    }

    // 获取封面数据
    var coverData = _audioHandler.currentArtworkData;
    if (coverData == null || coverData.isEmpty) {
      if (currentMusic.coverData != null && currentMusic.coverData!.isNotEmpty) {
        coverData = Uint8List.fromList(currentMusic.coverData!);
      }
    }

    // 构建 Widget 数据
    final widgetData = MediaWidgetData(
      title: currentMusic.displayTitle,
      artist: currentMusic.artist,
      album: currentMusic.album,
      isPlaying: state.isPlaying,
      progress: state.progress,
      currentTime: state.position.inSeconds,
      totalTime: state.duration.inSeconds,
      coverImageData: coverData,
    );

    await widgetDataService.updateMediaWidget(widgetData);
  }

  /// 设置 Android 灵动岛开关
  Future<void> setDynamicIslandEnabled({required bool enabled}) async {
    _dynamicIslandEnabled = enabled;
    if (!enabled) {
      await _hideDynamicIsland();
    } else if (_ref.read(currentMusicProvider) != null && state.isPlaying) {
      // 如果正在播放，显示灵动岛
      await _startDynamicIsland(
        music: _ref.read(currentMusicProvider)!,
        coverData: _audioHandler.currentArtworkData,
      );
    }
    logger.i('MusicPlayer: Android 灵动岛已${enabled ? "启用" : "禁用"}');
  }

  /// 配置 AudioSession
  /// 这是确保灵动岛/Now Playing 正常显示的关键配置
  ///
  /// 根据 Apple 文档，Now Playing 显示需要：
  /// 1. AVAudioSession 使用非 mixable 的 category（如 .playback）
  /// 2. 注册至少一个 remote command handler（由 audio_service 自动处理）
  /// 3. 正确设置 MPNowPlayingInfoCenter（由 audio_service 自动处理）
  ///
  /// 参考：https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter
  Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance;

      // 配置 AudioSession 为音乐播放模式
      // - category: playback - 音频应用，即使静音开关开启也播放
      // - mode: defaultMode - 默认模式
      // - 注意：不使用 mixWithOthers，这样系统才会将此 app 识别为 Now Playing app
      await session.configure(const AudioSessionConfiguration(
        // iOS 配置
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        // Android 配置
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ));

      logger.i('MusicPlayer: AudioSession 已配置为 playback category（非 mixable）');
    } on Exception catch (e) {
      logger.w('MusicPlayer: 配置 AudioSession 失败: $e');
    }
  }

  /// 初始化音频会话中断处理
  /// 处理来电、其他应用播放音频等中断事件
  Future<void> _initAudioSessionHandling() async {
    try {
      final session = await AudioSession.instance;

      // 监听音频中断事件（如来电、其他应用播放等）
      session.interruptionEventStream.listen((event) {
        logger.d('MusicPlayer: 音频中断事件 - begin=${event.begin}, type=${event.type}');
        if (event.begin) {
          // 中断开始
          switch (event.type) {
            case AudioInterruptionType.duck:
              // 降低音量（其他应用短暂播放）
              _audioHandler.setVolume(state.volume * 0.3);
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              // 暂停播放
              _audioHandler.pause();
          }
        } else {
          // 中断结束
          switch (event.type) {
            case AudioInterruptionType.duck:
              // 恢复音量
              _audioHandler.setVolume(state.volume);
            case AudioInterruptionType.pause:
              // 可选：恢复播放（某些应用可能不希望自动恢复）
              // _audioHandler.play();
              break;
            case AudioInterruptionType.unknown:
              break;
          }
        }
      });

      // 监听音频设备变化（如耳机拔出）
      session.becomingNoisyEventStream.listen((_) {
        logger.d('MusicPlayer: 音频设备变化（耳机拔出），暂停播放');
        _audioHandler.pause();
      });

      logger.i('MusicPlayer: 音频会话中断处理已初始化');
    } on Exception catch (e) {
      logger.w('MusicPlayer: 初始化音频会话中断处理失败: $e');
    }
  }

  /// 应用保存的设置
  Future<void> _applySettings() async {
    final settings = _ref.read(musicSettingsProvider);
    _targetVolume = settings.volume;
    await _audioHandler.setVolume(settings.volume);
    state = state.copyWith(
      volume: settings.volume,
      playMode: settings.playMode,
    );
  }

  /// 显式激活 Audio Session
  /// 这是确保 Live Activity 在后台正常工作的关键步骤
  /// iOS 的 Live Activity 需要 Audio Session 在 App 进入后台前被激活
  Future<void> _activateAudioSession() async {
    if (!Platform.isIOS) return;

    try {
      final session = await AudioSession.instance;
      // 显式激活 Audio Session
      // 这会通知系统应用即将播放音频，允许后台音频播放
      await session.setActive(true);
      logger.i('MusicPlayer: Audio Session 已激活');
    } on Exception catch (e) {
      // 激活失败不应阻止播放
      logger.w('MusicPlayer: Audio Session 激活失败: $e');
    }
  }

  /// 上次开始交叉淡化的时间，用于超时检测
  DateTime? _crossfadeStartTime;

  /// 交叉淡化超时时间（秒）
  static const int _crossfadeTimeoutSeconds = 30;

  void _onTrackCompleted() {
    final currentMusic = _ref.read(currentMusicProvider);
    logger.i('MusicPlayer: _onTrackCompleted 触发, '
        'isCrossfading=$_isCrossfading, '
        'currentMusic=${currentMusic?.name}');

    // 听歌统计：歌曲播完，结算当前会话
    AppError.fireAndForget(
      PlayHistoryStore.instance.endSession(),
      action: 'playHistory.endSession',
    );
    // Scrobble：歌曲播完，触发 50%/240s 阈值检查 + 上报
    AppError.fireAndForget(
      MusicScrobbleService.instance.endSession(),
      action: 'scrobble.endSession',
    );

    // 如果正在交叉淡化，检查是否超时
    if (_isCrossfading) {
      // 检查交叉淡化是否超时
      if (_crossfadeStartTime != null) {
        final elapsed = DateTime.now().difference(_crossfadeStartTime!).inSeconds;
        if (elapsed > _crossfadeTimeoutSeconds) {
          logger.w('MusicPlayer: 交叉淡化超时 (${elapsed}s > ${_crossfadeTimeoutSeconds}s)，强制重置状态');
          _isCrossfading = false;
          _crossfadeStartTime = null;
          // 继续执行后续逻辑，播放下一首
        } else {
          logger.d('MusicPlayer: 歌曲结束，交叉淡化已在处理中 (elapsed=${elapsed}s)');
          return;
        }
      } else {
        logger.d('MusicPlayer: 歌曲结束，交叉淡化已在处理中');
        return;
      }
    }

    logger.i('MusicPlayer: 歌曲播放完成，准备切换到下一首');

    // 重置状态
    _isFadingOut = false;
    _isFadingIn = false;
    AppError.fireAndForget(_cleanupPreload(), action: 'musicPlayer.cleanupPreload');

    switch (state.playMode) {
      case PlayMode.repeatOne:
        logger.d('MusicPlayer: 单曲循环模式，重新播放');
        AppError.fireAndForget(
          _repeatCurrentTrack(),
          action: 'repeatCurrentTrack',
        );
      case PlayMode.loop:
        logger.d('MusicPlayer: 列表循环模式，播放下一首');
        AppError.fireAndForget(
          _playNextWithRetry(),
          action: 'playNextOnComplete',
        );
      case PlayMode.shuffle:
        logger.d('MusicPlayer: 随机播放模式，播放下一首');
        AppError.fireAndForget(
          _playNextWithRetry(),
          action: 'playNextOnComplete',
        );
    }
  }

  /// 重复播放当前歌曲
  Future<void> _repeatCurrentTrack() async {
    try {
      await seek(Duration.zero);
      await _audioHandler.play();
    } on Exception catch (e, st) {
      logger.e('MusicPlayer: 重复播放失败', e, st);
      // 尝试重新播放当前歌曲
      final currentMusic = _ref.read(currentMusicProvider);
      if (currentMusic != null) {
        await play(currentMusic);
      }
    }
  }

  /// 播放下一首（带重试机制）
  Future<void> _playNextWithRetry() async {
    try {
      await playNext();
    } on Exception catch (e, st) {
      logger.e('MusicPlayer: 播放下一首失败，尝试重试', e, st);
      // 等待一小段时间后重试
      await Future<void>.delayed(const Duration(milliseconds: 500));
      try {
        await playNext();
      } on Exception catch (e2, st2) {
        logger.e('MusicPlayer: 播放下一首重试失败', e2, st2);
      }
    }
  }

  /// 清理预加载状态
  Future<void> _cleanupPreload() async {
    _preloadedMusic = null;
    _isPreloading = false;
    await _crossfadePlayer?.dispose();
    _crossfadePlayer = null;
  }

  /// 检查是否需要开始交叉淡化
  void _checkFadeOut(Duration position) {
    final settings = _ref.read(musicSettingsProvider);
    final crossfadeDuration = settings.crossfadeDuration;

    // 如果淡入淡出未启用，或者正在交叉淡化中，跳过
    if (crossfadeDuration <= 0 || _isCrossfading) return;

    final duration = state.duration;
    if (duration <= Duration.zero) return;

    // 计算距离结束的时间
    final remaining = duration - position;
    final preloadStart = Duration(seconds: crossfadeDuration + 2); // 提前2秒预加载
    final crossfadeStart = Duration(seconds: crossfadeDuration);

    // 预加载下一首（提前2秒）
    if (remaining <= preloadStart && remaining > crossfadeStart && !_isPreloading) {
      AppError.fireAndForget(
        _preloadNextTrack(),
        action: 'preloadNextTrack',
      );
    }

    // 开始交叉淡化
    if (remaining <= crossfadeStart && remaining > Duration.zero) {
      AppError.fireAndForget(
        _startCrossfade(remaining),
        action: 'startCrossfade',
      );
    }
  }

  /// 预加载下一首歌曲
  Future<void> _preloadNextTrack() async {
    if (_isPreloading || _preloadedMusic != null) return;

    final queue = _ref.read(playQueueProvider);
    if (queue.isEmpty) return;

    // 获取下一首歌曲
    final nextIndex = _getNextIndex();
    if (nextIndex < 0 || nextIndex >= queue.length) return;

    final nextMusic = queue[nextIndex];
    _isPreloading = true;

    logger.d('MusicPlayer: 预加载下一首 ${nextMusic.name}');

    try {
      // 获取下一首的播放 URL
      final url = await _getPlayableUrl(nextMusic);
      if (url == null) {
        logger.w('MusicPlayer: 预加载失败，无法获取 URL');
        _isPreloading = false;
        return;
      }

      // 创建辅助播放器并预加载
      await _crossfadePlayer?.dispose();
      _crossfadePlayer = AudioPlayer();
      await _crossfadePlayer!.setUrl(url);
      await _crossfadePlayer!.setVolume(0); // 初始音量为0

      _preloadedMusic = nextMusic;
      logger.i('MusicPlayer: 预加载完成 ${nextMusic.name}');
    } on Exception catch (e) {
      logger.e('MusicPlayer: 预加载失败', e);
      await _crossfadePlayer?.dispose();
      _crossfadePlayer = null;
    } finally {
      _isPreloading = false;
    }
  }

  /// 获取下一首的索引
  int _getNextIndex() {
    final queue = _ref.read(playQueueProvider);
    if (queue.isEmpty) return -1;

    if (state.playMode == PlayMode.shuffle) {
      if (queue.length == 1) return 0;
      int nextIndex;
      do {
        nextIndex = _random.nextInt(queue.length);
      } while (nextIndex == state.currentIndex);
      return nextIndex;
    } else {
      return (state.currentIndex + 1) % queue.length;
    }
  }

  /// 获取音乐的可播放 URL（用于预加载）
  Future<String?> _getPlayableUrl(MusicItem music) async {
    try {
      final uri = Uri.tryParse(music.url);
      if (uri == null || !uri.hasScheme) return null;

      // NCM 文件需要解密，暂时跳过预加载
      if (_isNcmFile(music.path) || _isNcmFile(music.name)) {
        logger.d('MusicPlayer: NCM 文件跳过预加载');
        return null;
      }

      if (music.sourceId != null) {
        // NAS 源：检查是否已有缓存
        final isCached = await _audioCacheService.isCached(music.sourceId, music.path);
        if (isCached) {
          final cacheFile = await _audioCacheService.getCacheFile(music.sourceId, music.path);
          return Uri.file(cacheFile.path).toString();
        }

        // 未缓存的 NAS 文件，需要创建代理 URL
        final connections = _ref.read(activeConnectionsProvider);
        final connection = connections[music.sourceId];
        if (connection == null) return null;

        final fileInfo = await connection.adapter.fileSystem.getFileInfo(music.path);
        final proxyUrl = await _mediaProxyServer.registerFile(
          sourceId: music.sourceId!,
          filePath: music.path,
          fileSize: fileInfo.size,
        );
        return proxyUrl;
      } else if (uri.scheme == 'file') {
        return music.url;
      } else if (uri.scheme == 'http' || uri.scheme == 'https') {
        return music.url;
      }

      return null;
    } on Exception catch (e) {
      logger.e('MusicPlayer: 获取可播放 URL 失败', e);
      return null;
    }
  }

  /// 开始交叉淡化
  /// 使用等功率曲线：保证 sin²(t) + cos²(t) = 1
  Future<void> _startCrossfade(Duration remaining) async {
    // 单曲循环不需要交叉淡化
    if (state.playMode == PlayMode.repeatOne) return;
    if (_isCrossfading) return;

    // 如果没有预加载的歌曲，回退到普通淡出
    if (_crossfadePlayer == null || _preloadedMusic == null) {
      logger.d('MusicPlayer: 无预加载，使用普通淡出');
      AppError.fireAndForget(
        _startSimpleFadeOut(remaining),
        action: 'simpleFadeOut',
      );
      return;
    }

    _isCrossfading = true;
    _crossfadeStartTime = DateTime.now();
    _isFadingOut = false;
    _isFadingIn = false;

    final fadeMs = remaining.inMilliseconds;
    final steps = (fadeMs / 16).ceil().clamp(10, 200);
    final stepMs = fadeMs ~/ steps;

    logger.i('MusicPlayer: 开始交叉淡化到 ${_preloadedMusic!.name}，时长 ${fadeMs}ms');

    try {
      // 启动辅助播放器
      await _crossfadePlayer!.play();

      // 同时调整两个播放器的音量
      for (var i = 0; i <= steps && _isCrossfading; i++) {
        final t = i / steps;

        // 等功率交叉淡化曲线
        // 当前歌曲：cos(t * π/2) - 从1降到0
        // 下一首：sin(t * π/2) - 从0升到1
        // 保证 sin²(t) + cos²(t) = 1，总功率恒定
        final fadeOutGain = math.cos(t * math.pi / 2);
        final fadeInGain = math.sin(t * math.pi / 2);

        await Future.wait([
          _audioHandler.setVolume((_targetVolume * fadeOutGain).clamp(0.0, 1.0)),
          _crossfadePlayer!.setVolume((_targetVolume * fadeInGain).clamp(0.0, 1.0)),
        ]);

        if (i < steps) {
          await Future<void>.delayed(Duration(milliseconds: stepMs));
        }
      }

      if (_isCrossfading) {
        // 交叉淡化完成，切换到新歌曲
        await _completeCrossfade();
      }
    } on Exception catch (e, st) {
      logger.e('MusicPlayer: 交叉淡化失败，回退到普通播放', e, st);
      // 重置状态
      _isCrossfading = false;
      _crossfadeStartTime = null;
      await _audioHandler.setVolume(_targetVolume);
      // 清理预加载
      await _cleanupPreload();
      // 尝试直接播放下一首
      await _playNextWithRetry();
    }
  }

  /// 完成交叉淡化，切换到新歌曲
  Future<void> _completeCrossfade() async {
    if (_preloadedMusic == null) {
      logger.w('MusicPlayer: _completeCrossfade 被调用但 _preloadedMusic 为 null');
      _isCrossfading = false;
      _crossfadeStartTime = null;
      return;
    }

    final nextMusic = _preloadedMusic!;
    final queue = _ref.read(playQueueProvider);
    final nextIndex = queue.indexWhere((m) => m.id == nextMusic.id);

    logger.i('MusicPlayer: 交叉淡化完成，切换到 ${nextMusic.name}');

    try {
      // 停止主播放器
      await _audioHandler.stopPlayer();
      await _audioHandler.setVolume(_targetVolume);

      // 停止辅助播放器（我们需要用主播放器继续播放以支持系统媒体控制）
      final crossfadePosition = _crossfadePlayer?.position ?? Duration.zero;
      await _crossfadePlayer?.stop();
      await _crossfadePlayer?.dispose();
      _crossfadePlayer = null;

      // 更新状态
      _ref.read(currentMusicProvider.notifier).state = nextMusic;
      if (nextIndex >= 0) {
        state = state.copyWith(currentIndex: nextIndex);
      }

      // 标记交叉淡化结束前清理状态
      _preloadedMusic = null;

      // 用主播放器从当前位置继续播放，跳过淡入效果（因为已经是满音量了）
      await play(nextMusic, startPosition: crossfadePosition, skipFadeIn: true);

      logger.i('MusicPlayer: 交叉淡化后播放成功: ${nextMusic.name}');
    } on Exception catch (e, st) {
      logger.e('MusicPlayer: 交叉淡化后播放失败，尝试重新播放', e, st);
      // 确保清理状态
      _preloadedMusic = null;
      await _cleanupPreload();
      
      // 尝试使用 playNextWithRetry 重新播放
      try {
        await _playNextWithRetry();
      } on Exception catch (e2, st2) {
        logger.e('MusicPlayer: 交叉淡化重试也失败了', e2, st2);
      }
    } finally {
      // 确保交叉淡化状态被重置
      _isCrossfading = false;
      _crossfadeStartTime = null;
    }
  }

  /// 简单淡出（当没有预加载时使用）
  Future<void> _startSimpleFadeOut(Duration remaining) async {
    if (_isFadingOut) return;
    _isFadingOut = true;

    final fadeMs = remaining.inMilliseconds;
    final steps = (fadeMs / 16).ceil().clamp(10, 200);
    final stepMs = fadeMs ~/ steps;

    logger.d('MusicPlayer: 开始简单淡出，剩余 ${fadeMs}ms');

    for (var i = 0; i <= steps && _isFadingOut; i++) {
      final t = i / steps;
      final gain = math.cos(t * math.pi / 2);
      final volume = _targetVolume * gain;
      await _audioHandler.setVolume(volume.clamp(0.0, 1.0));
      if (i < steps) {
        await Future<void>.delayed(Duration(milliseconds: stepMs));
      }
    }

    if (_isFadingOut) {
      await _audioHandler.setVolume(0);
    }
    _isFadingOut = false;
  }

  /// 定期保存播放状态
  void _savePlayStateIfNeeded(Duration position) {
    // 检查是否需要保存
    final now = DateTime.now();
    if (_lastStateSaveTime != null &&
        now.difference(_lastStateSaveTime!) < _stateSaveInterval) {
      return;
    }

    final currentMusic = _ref.read(currentMusicProvider);
    if (currentMusic == null) return;

    final queue = _ref.read(playQueueProvider);

    _lastStateSaveTime = now;
    AppError.fireAndForget(
      _favoritesService.saveLastPlayedState(
        music: currentMusic,
        position: position,
        queue: queue,
        queueIndex: state.currentIndex,
      ),
      action: 'savePlayState',
    );
  }

  /// 恢复上次播放状态
  Future<bool> restoreLastPlayedState() async {
    final lastState = await _favoritesService.getLastPlayedState();
    if (lastState == null) {
      logger.d('MusicPlayer: 没有保存的播放状态');
      return false;
    }

    logger.i('MusicPlayer: 恢复播放状态 ${lastState.music.name} @ ${lastState.position.inSeconds}s');

    // 恢复队列
    if (lastState.queue.isNotEmpty) {
      _ref.read(playQueueProvider.notifier).setQueue(lastState.queue);
      state = state.copyWith(currentIndex: lastState.queueIndex);
    }

    // 播放音乐，从上次位置开始
    await play(lastState.music, startPosition: lastState.position);
    return true;
  }

  /// 开始淡入
  /// 使用正弦曲线实现等功率淡入：sin(t * π/2)
  /// 这样音量变化在开始时快速上升，接近目标时变化缓慢，符合人耳感知
  Future<void> _startFadeIn() async {
    final settings = _ref.read(musicSettingsProvider);
    final crossfadeDuration = settings.crossfadeDuration;

    // 如果淡入淡出未启用，直接设置目标音量
    if (crossfadeDuration <= 0) {
      await _audioHandler.setVolume(_targetVolume);
      return;
    }

    _isFadingIn = true;
    _isFadingOut = false; // 取消任何正在进行的淡出

    // 从0开始淡入
    await _audioHandler.setVolume(0);

    final fadeMs = crossfadeDuration * 1000;
    // 使用更多步数获得更平滑的效果（约60步/秒）
    final steps = (fadeMs / 16).ceil().clamp(10, 200);
    final stepMs = fadeMs ~/ steps;

    logger.d('MusicPlayer: 开始淡入，时长 ${crossfadeDuration}s，步数 $steps');

    for (var i = 0; i <= steps && _isFadingIn; i++) {
      // 归一化进度 t: 0.0 -> 1.0
      final t = i / steps;
      // 正弦曲线淡入：sin(t * π/2)
      // t=0 时 sin(0)=0，t=1 时 sin(π/2)=1
      final gain = math.sin(t * math.pi / 2);
      final volume = _targetVolume * gain;
      await _audioHandler.setVolume(volume.clamp(0.0, 1.0));
      if (i < steps) {
        await Future<void>.delayed(Duration(milliseconds: stepMs));
      }
    }

    // 确保最终音量为目标音量
    if (_isFadingIn) {
      await _audioHandler.setVolume(_targetVolume);
    }
    _isFadingIn = false;
  }

  /// 播放指定音乐
  /// [skipFadeIn] 如果为 true，跳过淡入效果（用于交叉淡化完成后）
  Future<void> play(MusicItem music, {Duration? startPosition, bool skipFadeIn = false, bool isRetryAfterRepair = false}) async {
    // 防止并发播放操作
    // 如果已有播放操作进行中，等待一小段时间后再尝试
    if (_isPlayOperationInProgress && !isRetryAfterRepair) {
      logger.w('MusicPlayer: 播放操作进行中，跳过本次请求: ${music.name}');
      return;
    }

    _isPlayOperationInProgress = true;

    // 如果不是交叉淡化完成后的调用，清理预加载状态
    if (!_isCrossfading) {
      await _cleanupPreload();
    }

    _ref.read(currentMusicProvider.notifier).state = music;
    state = state.copyWith(isBuffering: true);

    // 听歌统计：开启新会话（内部会先 endSession 上一首）
    AppError.fireAndForget(
      PlayHistoryStore.instance.beginSession(music),
      action: 'playHistory.beginSession',
    );
    // Scrobble：开启新会话（now playing 上报 + 内部 endSession 上一首）
    AppError.fireAndForget(
      MusicScrobbleService.instance.beginSession(music),
      action: 'scrobble.beginSession',
    );

    logger..i('MusicPlayer: 开始播放 ${music.name}')
      ..d('MusicPlayer: URL => ${music.url}')
      ..d('MusicPlayer: size=${music.size}, path=${music.path}, sourceId=${music.sourceId}');

    // iOS 不支持格式检测：当使用 just_audio 引擎在 iOS 上播放 FLAC 等格式时
    // 通知 UI 层显示切换引擎的提示
    if (_isJustAudioEngine && isUnsupportedOnIosWithJustAudio(music.path)) {
      final formatName = _getFormatDisplayName(music.path);
      logger.w('MusicPlayer: 检测到 iOS 不支持的格式 $formatName，当前使用 just_audio 引擎');
      onUnsupportedFormatDetected?.call(formatName);
      // 继续尝试播放，可能会失败（让用户看到错误信息以便理解问题）
    }

    try {
      // 重要：在播放开始前显式激活 Audio Session
      // 这是确保 Live Activity 在后台正常工作的关键
      // 如果 Audio Session 没有在 App 进入后台前激活，Live Activity 可能不会出现
      await _activateAudioSession();

      // 重要：通过 audioHandler 准备切换歌曲
      // 这会正确暂停当前播放并广播状态，避免灵动岛内容不同步
      await _audioHandler.prepareForNewTrack();

      // 停止播放器并清理资源
      await _audioHandler.stopPlayer();
      _cleanupCurrentProxy();
      state = state.copyWith(position: Duration.zero, duration: Duration.zero);
      logger.d('MusicPlayer: 已停止当前播放并重置状态');

      // 验证 URL 格式
      final uri = Uri.tryParse(music.url);
      if (uri == null || !uri.hasScheme) {
        throw Exception('无效的音频 URL: ${music.url}');
      }
      logger.d('MusicPlayer: URI 解析成功 - scheme: ${uri.scheme}, host: ${uri.host}');

      // 根据音频来源选择合适的播放方式
      AudioSource audioSource;
      String audioSourceUrl; // 用于 MediaKit 模式
      var isCachedLocalFile = false; // 标记是否使用缓存文件播放，用于失败回退

      // 检查是否为 NCM 文件，需要先解密
      if (_isNcmFile(music.path) || _isNcmFile(music.name)) {
        logger.i('MusicPlayer: 检测到 NCM 文件，开始解密...');
        final decryptedFile = await _getDecryptedNcmFile(music);
        if (decryptedFile == null) {
          throw Exception('NCM 文件解密失败');
        }
        logger.i('MusicPlayer: 使用解密后的文件播放: ${decryptedFile.path}');
        audioSourceUrl = Uri.file(decryptedFile.path).toString();
        audioSource = AudioSource.uri(Uri.file(decryptedFile.path));
      } else if (music.sourceId != null) {
        // NAS 源：优先检查本地缓存，避免重复下载
        logger.d('MusicPlayer: 检测到 NAS 源 (sourceId=${music.sourceId})');

        // 检查是否已有完整缓存（包含文件大小验证）
        // 注意：LockCachingAudioSource 可能在缓存时混入额外数据导致大小不匹配
        final cacheFile = await _audioCacheService.getCacheFile(music.sourceId, music.path);
        final isCached = await _audioCacheService.isCachedWithSizeCheck(
          music.sourceId, 
          music.path,
          music.size ?? 0,
        );
        
        // 诊断日志：缓存状态
        final cacheExists = await cacheFile.exists();
        final cacheSize = cacheExists ? await cacheFile.length() : 0;
        final partFile = File('${cacheFile.path}.part');
        final partExists = await partFile.exists();
        logger.d('MusicPlayer: 缓存诊断 => '
            'file=${cacheFile.path}, '
            'exists=$cacheExists, '
            'cacheSize=$cacheSize, '
            'expectedSize=${music.size}, '
            'partExists=$partExists, '
            'isCached=$isCached');

        if (isCached) {
          // iOS 上使用 LockCachingAudioSource 播放缓存的 FLAC 文件
          // 因为 AudioSource.uri(file://) 无法正确解码 LockCachingAudioSource 生成的 FLAC 缓存
          // LockCachingAudioSource 会自动检测缓存是否存在并使用其内部机制读取
          if (Platform.isIOS && _isFlacFile(music.path)) {
            logger.i('MusicPlayer: iOS FLAC 使用 LockCachingAudioSource 播放缓存');
            final connections = _ref.read(activeConnectionsProvider);
            final connection = connections[music.sourceId];
            if (connection != null) {
              final proxyUrl = await _mediaProxyServer.registerFile(
                sourceId: music.sourceId!,
                filePath: music.path,
                fileSize: music.size ?? 0,
              );
              _currentProxyId = proxyUrl.split('/').last;
              audioSourceUrl = proxyUrl;
              // ignore: experimental_member_use
              audioSource = LockCachingAudioSource(
                Uri.parse(proxyUrl),
                cacheFile: cacheFile,
              );
            } else {
              // 连接不可用，回退到直接文件播放
              logger.w('MusicPlayer: iOS FLAC 连接不可用，使用直接文件播放');
              audioSourceUrl = Uri.file(cacheFile.path).toString();
              audioSource = AudioSource.uri(Uri.file(cacheFile.path));
              isCachedLocalFile = true;
            }
          } else {
            // 其他平台或非 FLAC 文件直接播放本地缓存
            logger.i('MusicPlayer: 使用本地缓存播放 ${cacheFile.path}');
            audioSourceUrl = Uri.file(cacheFile.path).toString();
            audioSource = AudioSource.uri(Uri.file(cacheFile.path));
            isCachedLocalFile = true; // 标记使用了缓存文件，用于失败时的回退处理
          }
        } else {
          // 无缓存，使用流式播放并缓存
          final connections = _ref.read(activeConnectionsProvider);
          final connection = connections[music.sourceId];

          if (connection == null) {
            throw Exception('源未连接，请先连接到 NAS: ${music.sourceId}');
          }

          // 获取文件大小
          final fileInfo = await connection.adapter.fileSystem.getFileInfo(music.path);
          final fileSize = fileInfo.size;

          // 确保缓存配额足够
          await _audioCacheService.ensureCacheQuota(newFileSize: fileSize);

          // 注册文件到代理服务器
          final proxyUrl = await _mediaProxyServer.registerFile(
            sourceId: music.sourceId!,
            filePath: music.path,
            fileSize: fileSize,
          );

          // 保存代理 ID 以便清理
          _currentProxyId = proxyUrl.split('/').last;

          logger..i('MusicPlayer: 使用流式播放模式 (边下边播并缓存到 ${cacheFile.path})')
          ..d('MusicPlayer: 代理URL => $proxyUrl');

          audioSourceUrl = proxyUrl;
          // 使用 LockCachingAudioSource 实现边下边播并自动缓存到指定文件
          // 这样下次播放相同歌曲时可以直接使用缓存
          // ignore: experimental_member_use
          audioSource = LockCachingAudioSource(
            Uri.parse(proxyUrl),
            cacheFile: cacheFile,
          );
        }
      } else if (uri.scheme == 'file') {
        // 本地文件：直接使用 URI
        logger.d('MusicPlayer: 本地文件');
        audioSourceUrl = uri.toString();
        audioSource = AudioSource.uri(uri);
      } else if (uri.scheme == 'http' || uri.scheme == 'https') {
        // HTTP/HTTPS URL：使用 LockCachingAudioSource 边下边播
        logger.d('MusicPlayer: 使用 HTTP/HTTPS URL (流式播放)');
        audioSourceUrl = uri.toString();
        // ignore: experimental_member_use
        audioSource = LockCachingAudioSource(uri);
      } else {
        throw Exception('不支持的音频协议: ${uri.scheme}');
      }

      // 设置音频源
      logger.d('MusicPlayer: 设置音频源...');
      Duration? playerDuration;
      
      // 标记是否使用了缓存文件（用于失败时的回退处理）
      final usedCacheFile = isCachedLocalFile && music.sourceId != null;
      
      try {
        if (_isJustAudioEngine && audioHandler is MusicAudioHandler) {
          // just_audio 模式：使用原始 AudioSource（支持 cacheFile 等特殊功能）
          playerDuration = await (audioHandler as MusicAudioHandler).setAudioSourceRaw(audioSource);
        } else {
          // MediaKit 模式：使用 URL 字符串
          playerDuration = await _audioHandler.setAudioSource(audioSourceUrl);
        }
      } on Exception catch (e, st) {
        // 如果使用缓存文件播放失败（常见于 iOS FLAC 偶发的 -11800 错误）
        // 注意：just_audio 会将 PlatformException 包装成 PlayerException
        // 删除可能损坏的缓存并使用流式播放重试
        if (usedCacheFile) {
          logger.w('MusicPlayer: 缓存播放失败 ($e)，删除缓存并重试流式播放');
          await _audioCacheService.deleteCache(music.sourceId, music.path);
          
          // 重新使用流式播放模式
          final connections = _ref.read(activeConnectionsProvider);
          final connection = connections[music.sourceId];
          if (connection != null) {
            final fileInfo = await connection.adapter.fileSystem.getFileInfo(music.path);
            final proxyUrl = await _mediaProxyServer.registerFile(
              sourceId: music.sourceId!,
              filePath: music.path,
              fileSize: fileInfo.size,
            );
            final cacheFile = await _audioCacheService.getCacheFile(music.sourceId, music.path);
            
            logger.i('MusicPlayer: 回退到流式播放模式');
            // ignore: experimental_member_use
            final streamingSource = LockCachingAudioSource(
              Uri.parse(proxyUrl),
              cacheFile: cacheFile,
            );
            
            if (_isJustAudioEngine && audioHandler is MusicAudioHandler) {
              playerDuration = await (audioHandler as MusicAudioHandler).setAudioSourceRaw(streamingSource);
            } else {
              playerDuration = await _audioHandler.setAudioSource(proxyUrl);
            }
          } else {
            // 无法获取连接，重新抛出原始异常
            AppError.handle(e, st, 'MusicPlayer.play.cachePlaybackFailed');
            rethrow;
          }
        } else {
          // 非缓存文件播放失败
          // 检查是否是 iOS FLAC -11800 错误，尝试自动修复
          final errorMessage = e.toString();
          if (Platform.isIOS && 
              _isFlacFile(music.path) && 
              errorMessage.contains('-11800')) {
            logger.w('MusicPlayer: iOS FLAC -11800 错误检测，尝试自动修复文件');
            
            // 尝试修复文件
            final repaired = await _tryRepairFlacFile(music);
            if (repaired) {
              // 修复成功，递归重试播放（设置标志防止无限循环）
              logger.i('MusicPlayer: FLAC 文件修复成功，重新尝试播放');
              // 注意：这里不递归调用 play()，而是抛出特殊异常让外层处理
              // 以避免递归调用导致的栈溢出风险
              throw FlacRepairedNeedRetryException(music);
            }
          }
          
          AppError.handle(e, st, 'MusicPlayer.play.setAudioSource');
          rethrow;
        }
      }
      
      logger.d('MusicPlayer: 音频源设置成功');

      // 获取播放器时长
      logger.i('MusicPlayer: 播放器时长 => $playerDuration');

      // 使用播放器时长或 MusicItem 的元数据时长
      var effectiveDuration = playerDuration;
      if ((effectiveDuration == null || effectiveDuration == Duration.zero) &&
          music.duration != null && music.duration! > Duration.zero) {
        effectiveDuration = music.duration;
        logger.i('MusicPlayer: 使用 MusicItem 的时长信息 => ${music.duration}');
      }

      if (effectiveDuration != null && effectiveDuration > Duration.zero) {
        state = state.copyWith(duration: effectiveDuration);
        logger.i('MusicPlayer: 最终时长 => $effectiveDuration');
      }

      // 跳转到指定位置
      if (startPosition != null && startPosition > Duration.zero) {
        logger.d('MusicPlayer: 跳转到位置 $startPosition');
        await _audioHandler.seekTo(startPosition);
      }

      // 获取淡入淡出设置
      final settings = _ref.read(musicSettingsProvider);
      final hasCrossfade = settings.crossfadeDuration > 0 && !skipFadeIn;

      // 如果启用了淡入淡出且不跳过，先将音量设为0，播放后再淡入
      if (hasCrossfade) {
        await _audioHandler.setVolume(0);
        logger.d('MusicPlayer: 淡入淡出已启用，初始音量设为0');
      } else {
        // 确保音量正确（交叉淡化完成后或未启用淡入淡出时）
        await _audioHandler.setVolume(_targetVolume);
        state = state.copyWith(volume: _targetVolume);
      }

      // 重要：在播放前设置 AudioHandler 的当前音乐信息
      // 这确保 iOS/Android 锁屏和控制中心能正确显示歌曲信息和控制按钮
      // 如果在 play() 之后设置，Now Playing 可能无法正确初始化
      Uint8List? coverData;
      if (music.coverData != null && music.coverData!.isNotEmpty) {
        coverData = Uint8List.fromList(music.coverData!);
      } else {
        // 尝试从封面缓存中获取
        final uniqueKey = '${music.sourceId ?? ''}_${music.path}';
        final coverCacheService = MusicCoverCacheService();
        coverData = await coverCacheService.getCover(uniqueKey);
      }
      await _audioHandler.setCurrentMusic(music, artworkData: coverData);

      // 启动 Android 灵动岛
      AppError.fireAndForget(
        _startDynamicIsland(music: music, coverData: coverData),
        action: 'musicPlayer.startDynamicIsland',
      );

      // 更新时长信息到 AudioHandler
      if (effectiveDuration != null && effectiveDuration > Duration.zero) {
        _audioHandler.updateDuration(effectiveDuration);
      }

      // 设置队列信息（如果有）
      final queue = _ref.read(playQueueProvider);
      if (queue.isNotEmpty) {
        final currentIndex = queue.indexWhere((m) => m.id == music.id);
        if (currentIndex >= 0) {
          _audioHandler.setQueue(queue, startIndex: currentIndex);
        }
      }

      // 开始播放
      logger.d('MusicPlayer: 调用 play()...');
      await _audioHandler.play(); // 使用 audioHandler.play() 确保正确广播状态
      logger.i('MusicPlayer: play() 调用完成');

      // 如果启用了淡入淡出，开始淡入（异步执行，不阻塞）
      if (hasCrossfade) {
        AppError.fireAndForget(
          _startFadeIn(),
          action: 'musicFadeIn',
        );
      }

      // 添加到播放历史
      await _ref.read(musicHistoryProvider.notifier).addToHistory(music);

      // 在后台提取元数据
      AppError.fireAndForget(
        _extractMetadataInBackground(music),
        action: 'extractMusicMetadata',
      );
    } on FlacRepairedNeedRetryException catch (e) {
      // FLAC 文件已修复，需要重试播放
      if (!isRetryAfterRepair) {
        logger.i('MusicPlayer: FLAC 文件已修复，重新尝试播放');
        _isPlayOperationInProgress = false;
        return play(e.music, startPosition: startPosition, skipFadeIn: skipFadeIn, isRetryAfterRepair: true);
      } else {
        // 已经是重试了，不再继续
        logger.e('MusicPlayer: FLAC 修复后仍然无法播放');
        state = state.copyWith(errorMessage: '播放失败: FLAC 文件兼容性问题', isBuffering: false);
      }
    } on Exception catch (e, stackTrace) {
      logger.e('MusicPlayer: 播放失败', e, stackTrace);
      state = state.copyWith(errorMessage: '播放失败: $e', isBuffering: false);
    } finally {
      // 重置播放操作标志
      _isPlayOperationInProgress = false;
    }
  }

  /// 清理当前代理的文件
  void _cleanupCurrentProxy() {
    if (_currentProxyId != null) {
      _mediaProxyServer.unregisterFile(_currentProxyId!);
      _currentProxyId = null;
    }
  }

  /// 检查是否为 NCM 文件
  bool _isNcmFile(String path) => p.extension(path).toLowerCase() == '.ncm';

  /// 检查是否为 FLAC 文件
  bool _isFlacFile(String path) => p.extension(path).toLowerCase() == '.flac';

  /// 尝试修复损坏的 FLAC 文件
  ///
  /// 使用 FFmpeg 重新复制文件以修复结构问题。
  /// 这对于被 audio_metadata_reader 修改后无法在 iOS 播放的文件特别有用。
  ///
  /// 参数:
  /// - [music]: 要修复的音乐文件
  ///
  /// 返回 true 表示修复成功，需要重新尝试播放
  Future<bool> _tryRepairFlacFile(MusicItem music) async {
    if (!Platform.isIOS || !_isFlacFile(music.path)) {
      return false;
    }

    try {
      logger.i('MusicPlayer: 尝试修复 FLAC 文件: ${music.path}');

      final connections = _ref.read(activeConnectionsProvider);
      final connection = connections[music.sourceId];
      if (connection == null) {
        logger.w('MusicPlayer: 无法获取连接，无法修复文件');
        return false;
      }

      final fileSystem = connection.adapter.fileSystem;
      final ffmpegService = FfmpegAudioTagService();

      // 确保 FFmpeg 可用
      if (!await ffmpegService.isAvailable()) {
        logger.w('MusicPlayer: FFmpeg 不可用，无法修复文件');
        return false;
      }

      // 下载原文件到临时目录
      final tempDir = await Directory.systemTemp.createTemp('flac_repair_');
      final tempInput = File('${tempDir.path}/input.flac');
      final tempOutput = File('${tempDir.path}/output.flac');

      try {
        // 下载文件
        logger.d('MusicPlayer: 下载 FLAC 文件用于修复...');
        final stream = await fileSystem.getFileStream(music.path);
        final sink = tempInput.openWrite();
        await for (final chunk in stream) {
          sink.add(chunk);
        }
        await sink.close();
        logger.d('MusicPlayer: FLAC 文件下载完成，大小: ${await tempInput.length()} 字节');

        // 使用 FFmpeg 修复
        final success = await ffmpegService.repairFlacFile(tempInput, tempOutput);
        if (!success) {
          logger.w('MusicPlayer: FFmpeg 修复失败');
          return false;
        }

        // 上传修复后的文件
        logger.d('MusicPlayer: 上传修复后的文件...');
        final repairedData = await tempOutput.readAsBytes();
        await fileSystem.writeFile(music.path, repairedData);

        // 删除本地缓存（文件已修改）
        await _audioCacheService.deleteCache(music.sourceId, music.path);

        logger.i('MusicPlayer: FLAC 文件修复完成');
        return true;
      } finally {
        // 清理临时文件
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'FLAC 文件修复失败');
      return false;
    }
  }

  /// 获取 NCM 解密后的缓存文件
  /// 如果已有缓存则直接返回，否则解密并缓存
  Future<File?> _getDecryptedNcmFile(MusicItem music) async {
    final sourceId = music.sourceId ?? 'local';
    final originalPath = music.path;

    // 计算缓存文件路径（去掉 .ncm 后缀，添加解密后的格式后缀）
    final cacheFile = await _audioCacheService.getCacheFile(sourceId, originalPath);

    // NCM 解密后的文件需要替换后缀
    // 先检查是否已有解密缓存（mp3 或 flac）
    final mp3Cache = File('${cacheFile.path.replaceAll('.ncm', '')}.mp3');
    final flacCache = File('${cacheFile.path.replaceAll('.ncm', '')}.flac');

    if (await mp3Cache.exists()) {
      logger.i('MusicPlayer: 使用已缓存的 NCM 解密文件 (MP3): ${mp3Cache.path}');
      return mp3Cache;
    }
    if (await flacCache.exists()) {
      logger.i('MusicPlayer: 使用已缓存的 NCM 解密文件 (FLAC): ${flacCache.path}');
      return flacCache;
    }

    // 需要解密
    Uint8List ncmData;

    if (music.sourceId != null) {
      // NAS 文件：下载
      logger.d('MusicPlayer: 从 NAS 下载 NCM 文件: ${music.path}');
      final connections = _ref.read(activeConnectionsProvider);
      final connection = connections[music.sourceId];

      if (connection == null) {
        logger.e('MusicPlayer: 源未连接: ${music.sourceId}');
        return null;
      }

      final stream = await connection.adapter.fileSystem.getFileStream(music.path);
      final chunks = <int>[];
      await for (final chunk in stream) {
        chunks.addAll(chunk);
      }
      ncmData = Uint8List.fromList(chunks);
    } else {
      // 本地文件
      final uri = Uri.tryParse(music.url);
      if (uri == null || uri.scheme != 'file') {
        logger.e('MusicPlayer: 无效的本地 NCM 文件路径: ${music.url}');
        return null;
      }
      final file = File(uri.toFilePath());
      if (!await file.exists()) {
        logger.e('MusicPlayer: NCM 文件不存在: ${file.path}');
        return null;
      }
      ncmData = await file.readAsBytes();
    }

    logger.d('MusicPlayer: NCM 文件大小: ${ncmData.length} bytes，开始解密...');

    // 解密
    final result = _ncmDecryptService.decrypt(ncmData);
    if (result == null) {
      logger.e('MusicPlayer: NCM 解密失败');
      return null;
    }

    // 根据元数据中的格式确定输出格式
    final format = result.metadata?.format.toLowerCase() ?? 'mp3';
    final outputFile = format == 'flac' ? flacCache : mp3Cache;

    // 确保父目录存在
    final parentDir = outputFile.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    // 保存解密后的音频
    await outputFile.writeAsBytes(result.audioData);
    logger.i('MusicPlayer: NCM 解密完成，保存到: ${outputFile.path} (${result.audioData.length} bytes)');

    return outputFile;
  }

  /// 基于文件大小估算音频时长
  /// 使用常见比特率估算，对于无法获取元数据的文件提供 fallback
  Duration? _estimateDurationFromFileSize(MusicItem music) {
    final fileSize = music.size;
    if (fileSize == null || fileSize <= 0) return null;

    // 根据文件扩展名选择估算比特率
    final ext = p.extension(music.name).toLowerCase();
    int estimatedBitrate; // kbps

    switch (ext) {
      case '.flac':
        // FLAC 通常是 800-1400 kbps，使用 1000 kbps 作为平均值
        estimatedBitrate = 1000;
      case '.wav':
        // WAV 通常是 1411 kbps (CD 质量)
        estimatedBitrate = 1411;
      case '.m4a':
      case '.aac':
        // AAC 通常是 128-256 kbps
        estimatedBitrate = 192;
      case '.ogg':
        // OGG 通常是 128-320 kbps
        estimatedBitrate = 192;
      case '.mp3':
      default:
        // MP3 通常是 128-320 kbps，使用 192 kbps 作为平均值
        estimatedBitrate = 192;
    }

    // 文件大小 (bytes) / (比特率 (kbps) * 1000 / 8) = 时长 (秒)
    // 简化：时长 (秒) = 文件大小 (bytes) * 8 / (比特率 (kbps) * 1000)
    final durationSeconds = (fileSize * 8) / (estimatedBitrate * 1000);

    // 验证结果是否合理（1秒到3小时之间）
    if (durationSeconds < 1 || durationSeconds > 10800) {
      logger.w('MusicPlayer: 估算时长不合理: ${durationSeconds}s, 跳过');
      return null;
    }

    return Duration(seconds: durationSeconds.round());
  }

  /// 在后台提取音乐元数据
  Future<void> _extractMetadataInBackground(MusicItem music) async {
    logger.d('MusicPlayer: 开始提取元数据 - name=${music.name}, sourceId=${music.sourceId}, url=${music.url}');

    // 检查是否需要提取元数据
    // 需要提取的情况：没有封面数据、没有歌词、或者没有时长
    final needsCover = music.coverData == null || music.coverData!.isEmpty;
    final needsLyrics = music.lyrics == null || music.lyrics!.isEmpty;
    final needsDuration = music.duration == null || music.duration == Duration.zero;

    // 如果所有元数据都已存在，跳过提取
    if (!needsCover && !needsLyrics && !needsDuration) {
      logger.d('MusicPlayer: 元数据完整，跳过提取 - hasCover=true, hasLyrics=true, hasDuration=true');
      return;
    }

    logger.d('MusicPlayer: 需要提取元数据 - needsCover=$needsCover, needsLyrics=$needsLyrics, needsDuration=$needsDuration');

    try {
      final metadataService = MusicMetadataService();
      await metadataService.init();

      MusicMetadata? metadata;

      // 优先根据 URL scheme 判断文件类型
      final uri = Uri.tryParse(music.url);
      logger.d('MusicPlayer: 解析URL - uri=$uri, scheme=${uri?.scheme}');

      if (uri != null && uri.scheme == 'file') {
        // 本地文件：直接从文件路径提取（无论是否有 sourceId）
        logger.d('MusicPlayer: 检测到本地文件 (file:// scheme)');
        final filePath = uri.toFilePath();
        logger.d('MusicPlayer: 文件路径 = $filePath');
        final file = File(filePath);
        final exists = await file.exists();
        logger.d('MusicPlayer: 文件存在 = $exists');

        if (exists) {
          logger.d('MusicPlayer: 开始从本地文件提取元数据...');
          metadata = await metadataService.extractFromLocalFile(file);
          logger.d('MusicPlayer: 提取完成 - metadata=${metadata != null}');
          if (metadata != null) {
            logger.d('MusicPlayer: 元数据详情 - title=${metadata.title}, artist=${metadata.artist}, album=${metadata.album}, hasCover=${metadata.coverData != null}, hasLyrics=${metadata.lyrics != null}');
          }
        }
      } else if (music.sourceId != null) {
        // NAS 文件（非 file:// scheme 且有 sourceId）：从连接中获取文件系统
        logger.d('MusicPlayer: 检测到 NAS 文件，sourceId=${music.sourceId}');
        final connections = _ref.read(activeConnectionsProvider);
        final connection = connections[music.sourceId];
        if (connection != null && connection.status == SourceStatus.connected) {
          metadata = await metadataService.extractFromNasFile(
            connection.adapter.fileSystem,
            music.path,
          );
        } else {
          logger.w('MusicPlayer: NAS连接不可用 - connection=${connection != null}, status=${connection?.status}');
        }
      } else {
        logger.w('MusicPlayer: 无法确定文件类型 - url=${music.url}, sourceId=${music.sourceId}');
      }

      if (metadata != null) {
        // 更新当前播放的音乐信息
        final updatedMusic = metadataService.applyMetadataToItem(music, metadata);
        final currentMusic = _ref.read(currentMusicProvider);
        logger.d('MusicPlayer: 当前播放ID=${currentMusic?.id}, 提取的音乐ID=${music.id}');

        if (currentMusic?.id == music.id) {
          _ref.read(currentMusicProvider.notifier).state = updatedMusic;
          logger.i('MusicPlayer: 元数据已更新 - artist=${metadata.artist}, album=${metadata.album}, hasCover=${metadata.coverData != null}, hasLyrics=${metadata.lyrics != null}, duration=${metadata.duration}');

          // 如果提取到了有效的 duration，且当前没有时长或者时长为零，更新播放器状态
          if (metadata.duration != null && metadata.duration! > Duration.zero) {
            final currentDuration = state.duration;
            // 更新条件：当前没有时长，或者元数据时长与当前时长差异较大（可能之前是估算值）
            final shouldUpdate = currentDuration == Duration.zero ||
                (currentDuration.inSeconds > 0 &&
                    (metadata.duration!.inSeconds - currentDuration.inSeconds).abs() >
                        currentDuration.inSeconds * 0.1); // 差异超过 10%

            if (shouldUpdate) {
              state = state.copyWith(duration: metadata.duration);
              logger.i('MusicPlayer: 从元数据更新播放器时长 => ${metadata.duration} (之前: $currentDuration)');
            }
          }

          // 更新 AudioHandler 封面（用于锁屏和控制中心显示专辑封面）
          if (metadata.coverData != null && metadata.coverData!.isNotEmpty) {
            final coverBytes = Uint8List.fromList(metadata.coverData!);
            AppError.fireAndForget(
              _audioHandler.updateArtwork(coverBytes),
              action: 'updateAudioHandlerArtwork',
            );
            // 更新 Android 灵动岛封面
            AppError.fireAndForget(
              _updateDynamicIsland(coverData: coverBytes),
              action: 'musicPlayer.updateDynamicIslandCover',
            );
          }
        } else {
          logger.w('MusicPlayer: 当前播放的音乐已变更，跳过更新');
        }
      } else {
        logger.w('MusicPlayer: 未能提取到元数据');
        // 元数据提取失败时，如果没有时长，尝试基于文件大小估算
        if (state.duration == Duration.zero) {
          final estimatedDuration = _estimateDurationFromFileSize(music);
          if (estimatedDuration != null && estimatedDuration > Duration.zero) {
            final currentMusic = _ref.read(currentMusicProvider);
            if (currentMusic?.id == music.id) {
              state = state.copyWith(duration: estimatedDuration);
              logger.i('MusicPlayer: 元数据提取失败，使用文件大小估算时长 => $estimatedDuration');
              _ref.read(currentMusicProvider.notifier).state = music.copyWith(duration: estimatedDuration);
            }
          }
        }
      }
    } on Exception catch (e, stackTrace) {
      logger.e('MusicPlayer: 提取元数据失败: $e', e, stackTrace);
      // 元数据提取异常时，如果没有时长，尝试基于文件大小估算
      if (state.duration == Duration.zero) {
        final estimatedDuration = _estimateDurationFromFileSize(music);
        if (estimatedDuration != null && estimatedDuration > Duration.zero) {
          final currentMusic = _ref.read(currentMusicProvider);
          if (currentMusic?.id == music.id) {
            state = state.copyWith(duration: estimatedDuration);
            logger.i('MusicPlayer: 元数据提取异常，使用文件大小估算时长 => $estimatedDuration');
            _ref.read(currentMusicProvider.notifier).state = music.copyWith(duration: estimatedDuration);
          }
        }
      }
    }
  }

  /// 播放队列中指定索引的音乐
  Future<void> playAt(int index) async {
    final queue = _ref.read(playQueueProvider);
    if (index >= 0 && index < queue.length) {
      state = state.copyWith(currentIndex: index);
      await play(queue[index]);
    }
  }

  /// 播放队列
  Future<void> playQueue(List<MusicItem> tracks, {int startIndex = 0}) async {
    _ref.read(playQueueProvider.notifier).setQueue(tracks);
    state = state.copyWith(currentIndex: startIndex);

    // 同步设置 AudioHandler 的队列
    // 这样锁屏和控制中心的上一首/下一首才能正确工作
    _audioHandler.setQueue(tracks, startIndex: startIndex);

    if (tracks.isNotEmpty && startIndex < tracks.length) {
      await play(tracks[startIndex]);
    }
  }

  /// Android Auto / CarPlay 浏览树触发播放：根据路径还原 MusicItem。
  ///
  /// 当前实现仅查 favorites + history 缓存（已经存了 musicUrl），命中即组队播放；
  /// 未命中的路径直接跳过。如果整批都未命中（用户访问了某个无缓存的歌单），
  /// 退化为不动作 —— 避免在车载场景里因为找不到 url 卡死或乱播。
  Future<void> _playFromBrowserPaths(
    List<({String? sourceId, String path})> entries,
    int startIndex,
  ) async {
    if (entries.isEmpty) return;
    final favSvc = MusicFavoritesService();
    await favSvc.init();
    final favs = await favSvc.getAllFavorites();
    final history = await favSvc.getRecentHistory(limit: 500);

    final favByPath = {for (final f in favs) f.musicPath: f};
    final histByPath = {for (final h in history) h.musicPath: h};

    final connections = _ref.read(activeConnectionsProvider);

    final items = <MusicItem>[];
    for (final e in entries) {
      // 先查 favorites / history 缓存（已带 musicUrl）
      final fav = favByPath[e.path];
      if (fav != null) {
        items.add(MusicBrowserService.buildMusicItemFromFavorite(fav));
        continue;
      }
      final h = histByPath[e.path];
      if (h != null) {
        items.add(MusicItem(
          id: '${h.sourceId ?? ''}_${h.musicPath}',
          name: h.musicName,
          path: h.musicPath,
          url: h.musicUrl,
          sourceId: h.sourceId,
          title: h.musicName,
          artist: h.artist,
          album: h.album,
          coverUrl: h.coverUrl,
          duration: h.duration,
        ));
        continue;
      }

      // 缓存未命中：用 sourceId 通过 NAS 适配器解析 URL
      final sid = e.sourceId;
      if (sid == null) continue;
      final conn = connections[sid];
      if (conn == null || conn.status != SourceStatus.connected) continue;
      try {
        final url = await conn.adapter.fileSystem.getFileUrl(e.path);
        items.add(MusicItem(
          id: '${sid}_${e.path}',
          name: _basenameOf(e.path),
          path: e.path,
          url: url,
          sourceId: sid,
          title: _basenameOf(e.path),
        ));
      } on Exception catch (ex, st) {
        AppError.handle(ex, st, 'browser.resolveUrl', {
          'sourceId': sid,
          'path': e.path,
        });
      }
    }
    if (items.isEmpty) {
      logger.w('MusicPlayer: browser play 队列为空（缓存未命中且 sourceId 缺失/未连接）');
      return;
    }
    final start = startIndex.clamp(0, items.length - 1);
    await playQueue(items, startIndex: start);
  }

  String _basenameOf(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }

  /// 播放/暂停切换
  Future<void> playOrPause() async {
    // 使用 state.isPlaying 而不是 _player.playing
    // 这样可以同时支持 just_audio 和 MediaKit 引擎
    if (state.isPlaying) {
      await _audioHandler.pause();
    } else {
      await _audioHandler.play();
    }
  }

  /// 暂停
  Future<void> pause() async {
    await _audioHandler.pause();
  }

  /// 继续播放
  Future<void> resume() async {
    await _audioHandler.play();
  }

  /// 停止
  Future<void> stop() async {
    await _audioHandler.stop();
    _cleanupCurrentProxy();
    state = state.copyWith(position: Duration.zero, duration: Duration.zero);
    _ref.read(currentMusicProvider.notifier).state = null;
    // 隐藏 Android 灵动岛
    AppError.fireAndForget(_hideDynamicIsland(), action: 'musicPlayer.hideDynamicIsland');
    // 清空 iOS/macOS 媒体小组件
    AppError.fireAndForget(widgetDataService.clearMediaWidget(), action: 'musicPlayer.clearMediaWidget');
  }

  /// 下一曲
  Future<void> playNext() async {
    final queue = _ref.read(playQueueProvider);
    if (queue.isEmpty) return;

    final nextIndex = _getNextIndex();
    if (nextIndex >= 0) {
      await playAt(nextIndex);
    }
  }

  /// 上一曲
  Future<void> playPrevious() async {
    final queue = _ref.read(playQueueProvider);
    if (queue.isEmpty) return;

    // 如果播放超过3秒，回到开头
    if (state.position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }

    final prevIndex =
        (state.currentIndex - 1 + queue.length) % queue.length;
    await playAt(prevIndex);
  }

  /// 跳转到指定位置
  Future<void> seek(Duration position) async {
    logger.d('MusicPlayer: seek => $position');

    try {
      // 使用 audioHandler.seek 确保 Now Playing 位置正确更新
      await _audioHandler.seek(position);
      // seek 完成后更新 state 以确保 UI 同步
      state = state.copyWith(position: position);
      logger.d('MusicPlayer: seek 完成');
    } on Exception catch (e) {
      logger.e('MusicPlayer: seek 失败: $e');
    }
  }

  /// 设置音量 (0.0 - 1.0)
  Future<void> setVolume(double volume) async {
    _targetVolume = volume;
    await _audioHandler.setVolume(volume);
    state = state.copyWith(volume: volume);
    // 同步保存到设置
    await _ref.read(musicSettingsProvider.notifier).setVolume(volume);
  }

  /// 设置音量（内部使用，不回调设置 provider）
  /// 由 MusicSettingsNotifier.setVolume 调用，避免循环调用
  Future<void> setVolumeInternal(double volume) async {
    final clampedVolume = volume.clamp(0.0, 1.0);
    _targetVolume = clampedVolume;
    await _audioHandler.setVolume(clampedVolume);
    state = state.copyWith(volume: clampedVolume);
  }

  /// 切换播放模式
  void togglePlayMode() {
    final modes = PlayMode.values;
    final nextIndex = (state.playMode.index + 1) % modes.length;
    final newMode = modes[nextIndex];
    state = state.copyWith(playMode: newMode);
    // 同步保存到设置
    _ref.read(musicSettingsProvider.notifier).setPlayMode(newMode);
  }

  /// 设置播放模式（仅更新播放器状态，不回调设置 provider）
  /// 由 MusicSettingsNotifier.setPlayMode 调用，避免循环调用
  void setPlayMode(PlayMode mode) {
    state = state.copyWith(playMode: mode);
    // 注意：不要在这里调用 musicSettingsProvider.notifier.setPlayMode
    // 否则会形成循环调用导致无限闪烁
  }


  /// 更新当前索引（用于队列重排序后同步）
  void updateCurrentIndex(int index) {
    state = state.copyWith(currentIndex: index);
  }

  @override
  void dispose() {
    _cleanupCurrentProxy();
    // 注意：不 dispose _audioHandler，因为它是全局单例
    // 它会在应用退出时自动清理
    super.dispose();
  }
}
