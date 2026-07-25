import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:just_audio/just_audio.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/audio_effects_service.dart';
import 'package:my_nas/features/music/data/services/music_audio_handler_interface.dart';
import 'package:my_nas/features/music/data/services/music_browser_service.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:path_provider/path_provider.dart';

/// 音乐播放 AudioHandler
/// 集成 just_audio 与 audio_service，实现后台音频播放和系统控制
///
/// 功能：
/// - iOS 锁屏和控制中心的媒体控制（上一首、暂停、下一首）
/// - Android 通知栏媒体控制
/// - 蓝牙耳机/AirPods 按钮控制
/// - CarPlay 支持
/// - 后台音频稳定播放
class MusicAudioHandler extends BaseAudioHandler
    with SeekHandler, WidgetsBindingObserver
    implements IMusicAudioHandler {
  MusicAudioHandler() {
    _init();
  }

  /// Android 端硬件均衡器。
  ///
  /// `AndroidEqualizer` 不能在 iOS/macOS 的音频管线中实例化，否则
  /// just_audio 会调用不存在的 Android 平台方法并导致整首歌曲无法加载。
  late final AndroidEqualizer? _androidEqualizer = Platform.isAndroid
      ? AndroidEqualizer()
      : null;

  late final AudioPlayer _player = Platform.isAndroid
      ? AudioPlayer(
          audioPipeline: AudioPipeline(
            androidAudioEffects: [_androidEqualizer!],
          ),
        )
      : AudioPlayer();

  StreamSubscription<EqualizerState>? _eqSub;

  /// 当前封面数据
  Uint8List? _currentArtworkData;

  /// 当前音乐项（用于保存额外的元数据）
  MusicItem? _currentMusicItem;

  /// 播放队列
  final List<MusicItem> _musicQueue = [];

  /// 当前队列索引
  int _currentIndex = 0;

  /// 封面文件缓存目录
  Directory? _artworkCacheDir;

  /// 播放器实例
  AudioPlayer get player => _player;

  /// 当前封面数据
  @override
  Uint8List? get currentArtworkData => _currentArtworkData;

  /// 当前索引
  @override
  int get currentIndex => _currentIndex;

  /// 获取当前音乐项
  @override
  MusicItem? get currentMusicItem => _currentMusicItem;

  /// 外部切歌回调（用于处理复杂的音频源加载）
  @override
  Future<void> Function(int index)? onSkipToIndex;

  Future<void> _init() async {
    // 延迟注册生命周期监听器，确保 WidgetsBinding 已就绪
    // 使用 addPostFrameCallback 确保在第一帧渲染后注册
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addObserver(this);
      logger.i('MusicAudioHandler: 生命周期监听器已注册');
    });

    // 初始化封面缓存目录
    await _initArtworkCacheDir();

    // 接入均衡器（仅 Android 真实生效；其他平台 no-op）
    AppError.fireAndForget(_initEqualizer(), action: 'justAudio.initEqualizer');

    // 监听播放状态变化，更新 playbackState
    _player.playbackEventStream.listen(_broadcastState);

    // 注意：不在这里监听播放完成，由 MusicPlayerNotifier._onTrackCompleted() 处理
    // MusicPlayerNotifier 会根据播放模式（列表循环/单曲循环/随机）决定下一步操作

    // 监听时长变化
    _player.durationStream.listen((duration) {
      if (duration != null && mediaItem.value != null) {
        mediaItem.add(mediaItem.value!.copyWith(duration: duration));
      }
    });

    // 监听位置变化（用于 Now Playing 的实时更新）
    _player.positionStream.listen((position) {
      // Now Playing 会自动根据 playbackState.updatePosition 和 speed 计算当前位置
      // 只有在 seek 时才需要手动更新，这里不需要做任何事
    });

    // 重要：广播初始 playbackState，确保系统知道可用的控制按钮
    // 如果不这样做，iOS/Android 在首次播放前不会显示控制按钮
    _broadcastState(PlaybackEvent());

    logger.i('MusicAudioHandler: 初始化完成');
  }

  /// 初始化封面缓存目录
  Future<void> _initArtworkCacheDir() async {
    try {
      final tempDir = await getTemporaryDirectory();
      _artworkCacheDir = Directory('${tempDir.path}/now_playing_artwork');
      if (!await _artworkCacheDir!.exists()) {
        await _artworkCacheDir!.create(recursive: true);
      }
      logger.d('MusicAudioHandler: 封面缓存目录已初始化: ${_artworkCacheDir!.path}');
    } on Exception catch (e) {
      logger.e('MusicAudioHandler: 初始化封面缓存目录失败: $e');
    }
  }

  /// iOS Now Playing 的最大封面尺寸
  /// 太大的图片会导致 iOS 无法正确显示或占用过多内存
  static const int _maxArtworkSize = 600;

  /// 保存封面到文件并返回文件 URI
  /// 使用文件 URI 而不是 data URL，因为 iOS 对大型 data URL 支持不好
  /// 同时会自动调整图片大小以适配 iOS Now Playing
  Future<Uri?> _saveArtworkToFile(Uint8List artworkData, String musicId) async {
    if (_artworkCacheDir == null) {
      await _initArtworkCacheDir();
    }
    if (_artworkCacheDir == null) {
      logger.w('MusicAudioHandler: 封面缓存目录未初始化');
      return null;
    }

    try {
      // 清理 musicId 中的特殊字符，确保文件名合法
      final safeId = musicId.replaceAll(RegExp(r'[^\w\-]'), '_');
      // 使用固定扩展名 jpg，因为调整大小后统一输出 JPEG
      final filePath = '${_artworkCacheDir!.path}/$safeId.jpg';
      final file = File(filePath);

      // 检查是否需要重新处理（文件不存在或源数据大小变化）
      // 使用 artworkData 长度的 hash 作为校验
      final hashPath = '${_artworkCacheDir!.path}/$safeId.hash';
      final hashFile = File(hashPath);
      final currentHash = artworkData.length.toString();
      String? existingHash;
      if (await hashFile.exists()) {
        existingHash = await hashFile.readAsString();
      }

      if (await file.exists() && existingHash == currentHash) {
        logger.d('MusicAudioHandler: 封面文件已存在且未变化，跳过处理');
        return Uri.file(filePath);
      }

      // 解码图片
      logger.d(
        'MusicAudioHandler: 开始处理封面图片 - 原始大小=${artworkData.length} bytes',
      );
      final originalImage = img.decodeImage(artworkData);
      if (originalImage == null) {
        logger.e('MusicAudioHandler: 无法解码封面图片');
        return null;
      }

      logger.d(
        'MusicAudioHandler: 原始尺寸=${originalImage.width}x${originalImage.height}',
      );

      // 如果图片太大，调整大小
      img.Image processedImage;
      if (originalImage.width > _maxArtworkSize ||
          originalImage.height > _maxArtworkSize) {
        // 保持宽高比，将较长边缩放到 _maxArtworkSize
        if (originalImage.width > originalImage.height) {
          processedImage = img.copyResize(
            originalImage,
            width: _maxArtworkSize,
          );
        } else {
          processedImage = img.copyResize(
            originalImage,
            height: _maxArtworkSize,
          );
        }
        logger.i(
          'MusicAudioHandler: 封面已调整大小 ${originalImage.width}x${originalImage.height} -> ${processedImage.width}x${processedImage.height}',
        );
      } else {
        processedImage = originalImage;
      }

      // 编码为 JPEG（更小的文件大小，更好的兼容性）
      final jpegData = img.encodeJpg(processedImage, quality: 85);
      await file.writeAsBytes(jpegData);

      // 保存 hash 以便下次比较
      await hashFile.writeAsString(currentHash);

      logger.i(
        'MusicAudioHandler: 封面已保存 - path=$filePath, size=${jpegData.length} bytes, dimensions=${processedImage.width}x${processedImage.height}',
      );

      // 验证文件是否存在
      if (!await file.exists()) {
        logger.e('MusicAudioHandler: 封面文件保存后不存在！');
        return null;
      }

      final uri = Uri.file(filePath);
      logger.i('MusicAudioHandler: 封面 URI = $uri');
      return uri;
    } on Exception catch (e, st) {
      logger.e('MusicAudioHandler: 保存封面文件失败: $e', e, st);
      return null;
    }
  }

  /// 处理 App 生命周期变化
  /// 当 App 从后台返回前台时，需要重新广播状态以刷新灵动岛/锁屏控制
  ///
  /// 重要修复（2024-12-28）：
  /// 之前在 inactive/hidden 状态调用 _resetMediaItemForNowPlaying() 会与原生层的
  /// forceRefreshNowPlayingInfo() 冲突，导致灵动岛闪烁。
  ///
  /// 日志证据：
  /// audio_service: forceRefreshNowPlayingInfo completed
  /// [NowPlayingInfo] Setting nowPlayingInfo with mergePolicy Replace: NULL
  /// [NowPlayingInfo] Clearing nowPlayingInfo
  ///
  /// 原因：Dart 层的 mediaItem.add() 触发 audio_service 更新 nowPlayingInfo，
  /// 覆盖了原生层刚设置的值。
  ///
  /// 解决方案：
  /// - 原生层通过 UIApplicationWillResignActiveNotification 处理灵动岛刷新
  /// - Dart 层只在 paused 状态广播播放状态，不调用 _resetMediaItemForNowPlaying()
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    logger.i(
      'MusicAudioHandler: App 生命周期变化 - $state, playing=${_player.playing}, hasMediaItem=${mediaItem.value != null}',
    );

    switch (state) {
      case AppLifecycleState.inactive:
        // App 即将进入后台（iOS 会先进入 inactive 再进入 paused）
        // 不在这里刷新！原生层会通过 UIApplicationWillResignActiveNotification 处理
        logger.d('MusicAudioHandler: App 进入 inactive 状态，等待原生层处理');

      case AppLifecycleState.hidden:
        // Flutter 3.13+ 新增的状态，在 inactive 和 paused 之间
        // 不在这里刷新！避免与原生层冲突
        logger.d('MusicAudioHandler: App 进入 hidden 状态，等待原生层处理');

      case AppLifecycleState.paused:
        // App 已进入后台 - iOS 在此时读取 MPNowPlayingInfoCenter 信息显示灵动岛
        //
        // 重要：灵动岛刷新现在 *完全* 由原生层处理：
        // - UIApplicationWillResignActiveNotification 触发 forceRefreshNowPlayingInfo
        // - UIApplicationDidEnterBackgroundNotification 作为备份再次刷新
        //
        // Dart 层在 paused 状态下 *不做任何操作*：
        // - 不调用 _resetMediaItemForNowPlaying()（避免 mediaItem 冲突）
        // - 不调用 _broadcastStateWithPlaying()（避免 playbackState 冲突）
        // 原因：任何 Dart 层的状态更新都可能触发 audio_service 原生层
        // 更新 nowPlayingInfo，与我们的 forceRefreshNowPlayingInfo 冲突，导致闪烁
        logger.d('MusicAudioHandler: App 已进入后台 (paused)，等待原生层处理灵动岛');

      case AppLifecycleState.resumed:
        // App 返回前台
        logger.i(
          'MusicAudioHandler: App 返回前台 (resumed), playing=${_player.playing}',
        );

        // 关键修复（2024-12-28 尝试十三）：
        // 根据 Apple 文档：音频会话可能在应用不活跃时被系统自动停用。
        // 必须在应用每次激活时显式重新激活音频会话。
        // 参考：https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/ConfiguringanAudioSession/ConfiguringanAudioSession.html
        //
        // 日志分析发现：
        // - iOS 检测 IsPlayingOutput:NO，系统认为没有实际音频输出
        // - DoesntActuallyPlayAudio = YES，系统认为应用不会实际播放音频
        // - 这导致再次进入后台时灵动岛不触发
        //
        // 解决方案：在返回前台时重新激活 AudioSession
        if (_player.playing && Platform.isIOS) {
          AppError.fireAndForget(
            _reactivateAudioSessionOnResumed(),
            action: 'audioHandler.reactivateAudioSession',
          );
        }

      case AppLifecycleState.detached:
        // App 即将被销毁，不需要处理
        break;
    }
  }

  /// 返回前台时重新激活 AudioSession（尝试十三）
  ///
  /// 根据 Apple 文档，音频会话可能在应用不活跃时被系统自动停用。
  /// 必须在应用每次激活时显式重新激活音频会话。
  ///
  /// 关键发现（日志分析）：
  /// - iOS 使用 `IsPlayingOutput` 检测是否有实际音频输出
  /// - 返回前台后，如果音频会话未激活，iOS 会设置 `IsPlayingOutput:NO`
  /// - 这导致再次进入后台时，灵动岛不会触发
  ///
  /// 解决方案：
  /// 1. 返回前台时立即重新激活 AudioSession
  /// 2. 延迟 200ms 后广播播放状态（确保在原生层 100ms 延迟后执行）
  Future<void> _reactivateAudioSessionOnResumed() async {
    try {
      final session = await AudioSession.instance;

      // 重新激活音频会话
      final success = await session.setActive(true);
      logger.i('MusicAudioHandler: 返回前台后重新激活 AudioSession, success=$success');

      // 延迟 200ms 后重新广播播放状态
      // 原生层会延迟 100ms 后设置 MPNowPlayingInfoCenter.playbackState
      // 我们在此之后再广播 Dart 层的 playbackState，确保顺序正确
      await Future<void>.delayed(const Duration(milliseconds: 200));

      if (_player.playing && mediaItem.value != null) {
        logger.i('MusicAudioHandler: 返回前台后重新广播播放状态');
        _broadcastStateWithPlaying(true);
      }
    } on Exception catch (e) {
      logger.w('MusicAudioHandler: 返回前台后重新激活 AudioSession 失败: $e');
    }
  }

  /// 刷新计数器
  int _refreshCounter = 0;

  /// 强制刷新 iOS Now Playing / 灵动岛
  ///
  /// 关键发现：iOS MediaRemote 框架在系统级别有去重机制
  /// 日志显示: "[NowPlayingInfo] Setting identical nowPlayingInfo, skipping update."
  /// 分析发现：iOS 只比较关键字段（title, artist, album, artwork）
  /// duration 和 position 的变化会被忽略
  ///
  /// 解决方案：
  /// 1. 有封面：重新保存 artwork 到新文件路径
  /// 2. 无封面：生成动态占位图片（每次颜色略微不同）
  ///
  /// 参考：
  /// - https://developer.apple.com/forums/thread/32475
  /// - https://github.com/ryanheise/audio_service/issues/684
  Future<void> _resetMediaItemForNowPlaying() async {
    final currentItem = mediaItem.value;
    if (currentItem == null) return;

    _refreshCounter++;

    final cleanTitle = currentItem.title.replaceAll('\u200B', '');
    logger.i(
      'MusicAudioHandler: 刷新灵动岛 (counter=$_refreshCounter) - $cleanTitle',
    );

    Uri? newArtUri;

    // 如果有封面数据，重新保存到新路径以触发 iOS 的 artwork 变化检测
    if (_currentArtworkData != null && _currentArtworkData!.isNotEmpty) {
      final timestampedId = '${currentItem.id}_refresh_$_refreshCounter';
      newArtUri = await _saveArtworkToFile(_currentArtworkData!, timestampedId);
      logger.d('MusicAudioHandler: 重新保存 artwork 到新路径: $newArtUri');
    } else {
      // 没有封面数据，使用原来的 artUri
      newArtUri = currentItem.artUri;
      logger.d('MusicAudioHandler: 无封面数据，保持原有 artUri');
    }

    // 创建修改后的 MediaItem
    final refreshedItem = MediaItem(
      id: currentItem.id,
      title: cleanTitle,
      artist: currentItem.artist,
      album: currentItem.album,
      duration: _player.duration ?? currentItem.duration ?? Duration.zero,
      artUri: newArtUri,
      extras: currentItem.extras,
    );

    // 更新 mediaItem（这会触发 audio_service 更新 nowPlayingInfo）
    mediaItem.add(refreshedItem);

    // 广播当前播放状态
    _broadcastStateWithPlaying(_player.playing);

    logger.i('MusicAudioHandler: 灵动岛刷新完成 - counter=$_refreshCounter');
  }

  /// 广播指定的播放状态
  void _broadcastStateWithPlaying(bool playing) {
    final processingState = _mapProcessingState(_player.processingState);

    playbackState.add(
      playbackState.value.copyWith(
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
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _currentIndex,
      ),
    );
  }

  /// 广播播放状态
  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    final processingState = _mapProcessingState(_player.processingState);

    // logger.d('MusicAudioHandler: 广播状态 - playing=$playing, processingState=$processingState, position=${_player.position}, hasMediaItem=${mediaItem.value != null}');

    playbackState.add(
      playbackState.value.copyWith(
        // 显示的控制按钮
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        // 允许的系统操作
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        // Android 紧凑视图显示的按钮索引
        androidCompactActionIndices: const [0, 1, 3],
        // 处理状态
        processingState: processingState,
        // 是否正在播放
        playing: playing,
        // 当前位置（用于 Now Playing 计算）
        updatePosition: _player.position,
        // 缓冲位置
        bufferedPosition: _player.bufferedPosition,
        // 播放速度
        speed: _player.speed,
        // 队列索引
        queueIndex: _currentIndex,
      ),
    );
  }

  /// 映射 just_audio 的处理状态到 audio_service
  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  /// 准备切换到新歌曲
  /// 在设置新歌曲之前调用，确保旧的播放状态被正确清理
  @override
  Future<void> prepareForNewTrack() async {
    logger.i(
      'MusicAudioHandler: 准备切换歌曲, 当前歌曲=${_currentMusicItem?.displayTitle}',
    );

    // 如果正在播放，先暂停并广播状态
    if (_player.playing) {
      await _player.pause();
      _broadcastState(PlaybackEvent());
    }

    // 重要：清理当前音乐信息，允许设置新歌曲
    _currentMusicItem = null;
    _currentArtworkData = null;

    logger.d('MusicAudioHandler: 已清理当前歌曲信息');
  }

  /// 设置当前播放的音乐（由 MusicPlayerNotifier 调用）
  @override
  Future<void> setCurrentMusic(
    MusicItem music, {
    Uint8List? artworkData,
  }) async {
    logger.i(
      'MusicAudioHandler: setCurrentMusic 被调用 - ${music.displayTitle}, hasArtwork=${artworkData != null}',
    );

    _currentMusicItem = music;
    _currentArtworkData = artworkData;

    // 将封面保存到文件并获取文件 URI
    // 使用文件 URI 而不是 data URL，因为 iOS 对大型 data URL 支持不好
    Uri? artUri;
    if (artworkData != null && artworkData.isNotEmpty) {
      artUri = await _saveArtworkToFile(artworkData, music.id);
      logger.d('MusicAudioHandler: 封面 URI = $artUri');
    }

    // 创建 MediaItem 用于 Now Playing 显示
    final item = MediaItem(
      id: music.id,
      title: music.displayTitle,
      artist: music.displayArtist,
      album: music.displayAlbum,
      duration: music.duration ?? Duration.zero,
      // 封面图片 - 使用文件 URI
      // audio_service 会自动将这个显示在锁屏和控制中心
      artUri: artUri,
      extras: {'sourceId': music.sourceId, 'path': music.path},
    );

    mediaItem.add(item);

    // 重要：设置 mediaItem 后立即广播 playbackState
    // 这确保 iOS Now Playing 能正确识别媒体信息和控制按钮
    _broadcastState(PlaybackEvent());

    logger.i(
      'MusicAudioHandler: 设置当前音乐 - ${music.displayTitle} by ${music.displayArtist}, hasArtwork=${artUri != null}',
    );

    // 注意：移除了 iOS 延迟刷新代码（2024-12-28）
    // 原因：这个 500ms 延迟刷新会在歌曲开始播放后触发第二次 mediaItem.add()，
    // 导致灵动岛闪烁（在 13ms 内发生两次 invalidate + create 循环）
    // 灵动岛刷新现在完全由原生层在进入后台时处理（通过 UIApplicationWillResignActiveNotification）
  }

  /// 更新封面图片（用于元数据加载完成后）
  @override
  Future<void> updateArtwork(Uint8List artworkData) async {
    _currentArtworkData = artworkData;

    if (mediaItem.value != null) {
      // 保存封面到文件
      final artUri = await _saveArtworkToFile(artworkData, mediaItem.value!.id);

      final updated = mediaItem.value!.copyWith(artUri: artUri);
      mediaItem.add(updated);

      // 重新广播状态以刷新 Now Playing
      _broadcastState(PlaybackEvent());

      logger.i('MusicAudioHandler: 封面图片已更新, artUri=$artUri');
    }
  }

  /// 更新时长
  @override
  void updateDuration(Duration duration) {
    if (mediaItem.value != null && duration > Duration.zero) {
      mediaItem.add(mediaItem.value!.copyWith(duration: duration));
    }
  }

  /// 设置播放队列
  @override
  void setQueue(List<MusicItem> items, {int startIndex = 0}) {
    _musicQueue
      ..clear()
      ..addAll(items);
    _currentIndex = startIndex;

    // 转换为 MediaItem 列表并更新 queue
    final mediaItems = items
        .map(
          (m) => MediaItem(
            id: m.id,
            title: m.displayTitle,
            artist: m.displayArtist,
            album: m.displayAlbum,
            duration: m.duration,
          ),
        )
        .toList();
    queue.add(mediaItems);

    logger.d('MusicAudioHandler: 设置队列 ${items.length} 首歌，起始索引 $startIndex');
  }

  /// 更新当前索引
  @override
  void updateCurrentIndex(int index) {
    _currentIndex = index;
    // 触发状态更新
    _broadcastState(PlaybackEvent());
  }

  @override
  Future<void> play() async {
    logger.i('MusicAudioHandler: play() 被调用');
    if (_player.processingState == ProcessingState.idle) {
      throw StateError('Audio source is not ready');
    }
    // 注意：不等待 _player.play()，因为在 iOS 上它可能不会立即返回
    // 这会导致调用者永远等待，进而导致切歌失败
    // play() 只是触发播放，实际的播放状态通过 playbackEventStream 监听
    AppError.fireAndForget(_player.play(), action: 'audioHandler.play');
    // 短暂等待确保播放器状态更新
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // 重要：显式广播状态确保 iOS Now Playing 立即更新
    _broadcastState(PlaybackEvent());
    logger.i('MusicAudioHandler: play() 完成，已广播状态');
  }

  @override
  Future<void> pause() async {
    logger.i('MusicAudioHandler: pause() 被调用');
    // 同样不等待，避免卡住
    AppError.fireAndForget(_player.pause(), action: 'audioHandler.pause');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // 显式广播状态确保 iOS Now Playing 立即更新
    _broadcastState(PlaybackEvent());
  }

  @override
  Future<void> stop() async {
    logger.i('MusicAudioHandler: stop() 被调用');
    // 同样不等待，避免卡住
    AppError.fireAndForget(_player.stop(), action: 'audioHandler.stop');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // 显式广播状态确保 iOS Now Playing 立即更新
    _broadcastState(PlaybackEvent());
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    // seek 后需要立即更新 playbackState 以保证 Now Playing 同步
    _broadcastState(PlaybackEvent());
  }

  @override
  Future<void> skipToNext() async {
    logger.i(
      'MusicAudioHandler: skipToNext() 被调用 (来自灵动岛/锁屏/控制中心), queueLength=${_musicQueue.length}, currentIndex=$_currentIndex',
    );
    if (_musicQueue.isEmpty) {
      logger.w('MusicAudioHandler: skipToNext() 队列为空，忽略');
      return;
    }

    final nextIndex = (_currentIndex + 1) % _musicQueue.length;
    logger.d('MusicAudioHandler: skipToNext() 切换到索引 $nextIndex');
    await _skipToIndex(nextIndex);
  }

  @override
  Future<void> skipToPrevious() async {
    logger.i(
      'MusicAudioHandler: skipToPrevious() 被调用 (来自灵动岛/锁屏/控制中心), queueLength=${_musicQueue.length}, currentIndex=$_currentIndex, position=${_player.position}',
    );
    if (_musicQueue.isEmpty) {
      logger.w('MusicAudioHandler: skipToPrevious() 队列为空，忽略');
      return;
    }

    // 如果播放超过3秒，回到开头
    if (_player.position.inSeconds > 3) {
      logger.d('MusicAudioHandler: skipToPrevious() 播放超过3秒，回到开头');
      await seek(Duration.zero);
      return;
    }

    final prevIndex =
        (_currentIndex - 1 + _musicQueue.length) % _musicQueue.length;
    logger.d('MusicAudioHandler: skipToPrevious() 切换到索引 $prevIndex');
    await _skipToIndex(prevIndex);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    logger.d('MusicAudioHandler: skipToQueueItem($index) 被调用');
    await _skipToIndex(index);
  }

  Future<void> _skipToIndex(int index) async {
    if (index < 0 || index >= _musicQueue.length) {
      logger.w(
        'MusicAudioHandler: _skipToIndex($index) 索引超出范围 [0, ${_musicQueue.length})',
      );
      return;
    }

    _currentIndex = index;
    logger.i(
      'MusicAudioHandler: _skipToIndex($index) 开始切换歌曲, hasCallback=${onSkipToIndex != null}',
    );

    // 调用外部回调处理音频源加载（因为涉及复杂的 NAS 文件处理）
    if (onSkipToIndex != null) {
      await onSkipToIndex!(index);
      logger.d('MusicAudioHandler: _skipToIndex($index) 回调执行完成');
    }
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    // 由 MusicPlayerNotifier 处理
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    // 由 MusicPlayerNotifier 处理
  }

  /// 当前音量
  double _volume = 1.0;

  /// 设置音量
  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    await _player.setVolume(volume);
  }

  /// 获取当前音量
  @override
  double get volume => _volume;

  /// 设置音频源（接口方法）
  ///
  /// [url] 音频文件 URL（支持 file://, http://, https://）
  /// [headers] HTTP 请求头（可选）
  @override
  Future<Duration?> setAudioSource(
    String url, {
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse(url);
    AudioSource audioSource;

    if (uri.scheme == 'file') {
      audioSource = AudioSource.uri(uri);
    } else if (uri.scheme == 'http' || uri.scheme == 'https') {
      if (headers != null && headers.isNotEmpty) {
        audioSource = AudioSource.uri(uri, headers: headers);
      } else {
        // ignore: experimental_member_use
        audioSource = LockCachingAudioSource(uri);
      }
    } else {
      audioSource = AudioSource.uri(uri);
    }

    return _player.setAudioSource(audioSource);
  }

  /// 设置音频源（内部方法，直接使用 AudioSource）
  Future<Duration?> setAudioSourceRaw(AudioSource source) =>
      _player.setAudioSource(source);

  /// 停止播放器
  @override
  Future<void> stopPlayer() => _player.stop();

  /// 跳转到指定位置
  @override
  Future<void> seekTo(Duration position) => _player.seek(position);

  // ==================== Stream 访问器 ====================

  /// 播放位置流
  @override
  Stream<Duration> get positionStream => _player.positionStream;

  /// 缓冲位置流
  @override
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;

  /// 时长流
  @override
  Stream<Duration> get durationStream =>
      _player.durationStream.where((d) => d != null).map((d) => d!);

  /// 播放状态流
  @override
  Stream<bool> get playingStream => _player.playingStream;

  /// 缓冲状态流
  @override
  Stream<bool> get bufferingStream => _player.processingStateStream.map(
    (state) =>
        state == ProcessingState.buffering || state == ProcessingState.loading,
  );

  /// 播放完成流
  /// 使用 distinct 确保只有状态变化时才发出事件
  /// 这避免了快速的状态变化（completed -> idle）导致事件丢失
  @override
  Stream<bool> get completedStream => _player.processingStateStream
      .map((state) => state == ProcessingState.completed)
      .distinct();

  // ==================== 刷新 Now Playing ====================

  /// 强制刷新 Now Playing / 灵动岛（公开方法）
  @override
  Future<void> refreshNowPlaying() async {
    await _resetMediaItemForNowPlaying();
  }

  // ============ MediaBrowserService（Android Auto / CarPlay）============

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) => MusicBrowserService.instance.getChildren(parentMediaId);

  @override
  Future<MediaItem?> getMediaItem(String mediaId) =>
      MusicBrowserService.instance.getMediaItem(mediaId);

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) => MusicBrowserService.instance.playFromMediaId(mediaId);

  @override
  Future<void> playFromSearch(String query, [Map<String, dynamic>? extras]) =>
      MusicBrowserService.instance.playFromSearch(query);

  @override
  Future<List<MediaItem>> search(
    String query, [
    Map<String, dynamic>? extras,
  ]) => MusicBrowserService.instance.search(query);

  /// 接入均衡器：初始应用一次 + 订阅后续变化
  Future<void> _initEqualizer() async {
    if (!Platform.isAndroid) {
      // 其他平台 AndroidEqualizer 不会生效（pipeline 内部 no-op），直接退出
      return;
    }
    await AudioEffectsService.instance.init();
    await _applyEqualizer(AudioEffectsService.instance.state);
    _eqSub = AudioEffectsService.instance.onChange.listen((state) {
      AppError.fireAndForget(
        _applyEqualizer(state),
        action: 'justAudio.applyEqualizer',
      );
    });
  }

  Future<void> _applyEqualizer(EqualizerState state) async {
    final equalizer = _androidEqualizer;
    if (equalizer == null) return;

    try {
      await equalizer.setEnabled(state.enabled);
      if (!state.enabled) return;
      final params = await equalizer.parameters;
      final bands = params.bands;
      // bands 数量由系统决定（一般 5 / 10），按比例线性插值
      for (var i = 0; i < bands.length; i++) {
        final t = bands.length == 1 ? 0.0 : i / (bands.length - 1);
        final srcIdx = (t * (state.gains.length - 1)).round();
        final gainDb = state.gains[srcIdx].clamp(kEqMinGain, kEqMaxGain);
        await bands[i].setGain(gainDb);
      }
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'justAudio.applyEqualizer');
    }
  }

  /// 释放资源
  @override
  Future<void> dispose() async {
    // 移除生命周期监听器
    WidgetsBinding.instance.removeObserver(this);
    await _eqSub?.cancel();
    await _player.dispose();
  }
}

/// 全局 AudioHandler 初始化
/// 在 main.dart 中调用
Future<MusicAudioHandler> initAudioHandler() => AudioService.init(
  builder: MusicAudioHandler.new,
  config: AudioServiceConfig(
    // Android 通知渠道配置
    androidNotificationChannelId: 'com.kkape.mynas.channel.audio',
    androidNotificationChannelName:
        appL10n.musicAudioHandlerNotificationChannelName,
    androidNotificationChannelDescription:
        appL10n.musicAudioHandlerNotificationChannelDescription,
    // Android 通知配置
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
    // 快进/快退间隔
    fastForwardInterval: Duration(seconds: 10),
    rewindInterval: Duration(seconds: 10),
    // 预加载（iOS 不需要，但对 Android 有帮助）
    preloadArtwork: true,
    // 通知点击后的行为
    androidNotificationClickStartsActivity: true,
  ),
);
