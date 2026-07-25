import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/core/widgets/keyboard_shortcuts.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/transfer/presentation/providers/transfer_provider.dart';
import 'package:my_nas/features/transfer/presentation/widgets/transfer_sheet.dart';
import 'package:my_nas/features/video/data/services/subtitle_service.dart';
import 'package:my_nas/features/video/data/services/video_metadata_service.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/presentation/providers/playback_settings_provider.dart';
import 'package:my_nas/features/video/presentation/providers/playlist_provider.dart';
import 'package:my_nas/features/video/presentation/providers/subtitle_style_provider.dart';
import 'package:my_nas/features/video/presentation/providers/video_player_provider.dart';
import 'package:my_nas/features/video/presentation/widgets/aspect_ratio_selector.dart';
import 'package:my_nas/features/video/presentation/widgets/bookmark_sheet.dart';
import 'package:my_nas/features/video/presentation/widgets/video_controls.dart';
import 'package:my_nas/features/video/presentation/widgets/video_gesture_controller.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/providers/bottom_nav_visibility_provider.dart';
import 'package:my_nas/shared/services/native_tab_bar_service.dart';
import 'package:screen_brightness/screen_brightness.dart';

class VideoPlayerPage extends ConsumerStatefulWidget {
  const VideoPlayerPage({required this.video, super.key});

  final VideoItem video;

  @override
  ConsumerState<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends ConsumerState<VideoPlayerPage>
    with WidgetsBindingObserver {
  bool _showControls = true;
  bool _isLocked = false;
  Timer? _hideControlsTimer;

  // 桌面端：鼠标是否在视频区域内
  bool _isMouseInVideoArea = false;

  // 桌面端：鼠标退出防抖计时器
  Timer? _mouseExitDebounceTimer;

  // 双击动画
  bool _showDoubleTapLeft = false;
  bool _showDoubleTapRight = false;

  // 缓存 notifier 引用，避免在 dispose 后使用 ref
  VideoPlayerNotifier? _playerNotifier;

  // 缓存源信息，用于 dispose 时更新缩略图
  String? _sourceId;
  NasFileSystem? _fileSystem;
  String? _videoUrl;

  // 缓存 provider 引用，避免异步操作后使用 ref
  Map<String, SourceConnection>? _connections;
  StateController<List<SubtitleItem>>? _subtitlesNotifier;

  // 记录上一次的横竖屏状态，避免重复设置
  Orientation? _lastOrientation;

  // 画中画支持状态
  bool _isPipSupported = false;

  // 是否为移动设备（支持手势控制亮度/音量）
  bool get _isMobile => Platform.isIOS || Platform.isAndroid;

  // 是否为桌面设备（支持鼠标悬停显示控制栏）
  bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  // 初始亮度，用于退出时恢复
  double? _initialBrightness;

  @override
  void initState() {
    super.initState();
    // 注册生命周期观察者
    WidgetsBinding.instance.addObserver(this);
    // 隐藏原生 Tab Bar（iOS 玻璃风格）
    NativeTabBarService.instance.setTabBarVisible(false);
    // 隐藏 Flutter 导航栏（经典风格）
    BottomNavVisibilityNotifier.instance?.hide();
    // 缓存 notifier 引用（在 widget 销毁前保存，避免异步操作后使用 ref）
    _playerNotifier = ref.read(videoPlayerControllerProvider.notifier);
    _connections = ref.read(activeConnectionsProvider);
    _subtitlesNotifier = ref.read(availableSubtitlesProvider.notifier);

    // 开始播放并缓存源信息
    Future.microtask(() async {
      if (!mounted) return;
      // 视频和音乐共用底层音频输出：先停止音乐，避免设备占用、
      // 声音重叠或切入视频后仍保留旧的 Now Playing 状态。
      if (ref.read(currentMusicProvider) != null) {
        await ref.read(musicPlayerControllerProvider.notifier).stop();
      }
      if (!mounted) return;
      // 移动设备：保存初始亮度，用于退出时恢复
      if (_isMobile) {
        try {
          _initialBrightness = await ScreenBrightness.instance.application;
        } on Exception catch (e) {
          logger.w('VideoPlayerPage: 获取初始亮度失败', e);
        }
      }
      if (!mounted) return;
      // 缓存源信息（用于 dispose 时更新缩略图）
      await _cacheSourceInfo();
      if (!mounted) return;
      // 检查画中画支持
      await _checkPipSupport();
      if (!mounted) return;
      // 初始化画中画状态监听
      _playerNotifier?.initPipStatusListener();
      // 开始播放
      await _playerNotifier?.play(
        widget.video,
        startPosition: widget.video.lastPosition,
      );
      if (!mounted) return;
      // 应用保存的字幕延时设置
      final subtitleStyle = ref.read(subtitleStyleProvider);
      if (subtitleStyle.delay != 0) {
        final notifier = _playerNotifier;
        if (notifier != null) {
          AppError.fireAndForget(
            notifier.setSubtitleDelay(subtitleStyle.delay),
            action: 'videoPlayer.applyInitialSubtitleDelay',
          );
        }
      }
      // 异步加载字幕，不阻塞播放流程
      AppError.fireAndForget(
        _loadSubtitles(),
        action: 'videoPlayer.loadSubtitles',
      );
    });
    _startHideControlsTimer();
  }

  /// 检查画中画支持
  Future<void> _checkPipSupport() async {
    final supported = await _playerNotifier?.isPipSupported ?? false;
    if (mounted) {
      setState(() => _isPipSupported = supported);
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // 检测屏幕方向变化，自动切换全屏状态
    _checkOrientationAndSetFullscreen();
  }

  /// 根据屏幕方向记录状态（不再自动设置全屏）
  void _checkOrientationAndSetFullscreen() {
    if (!mounted) return;

    final size =
        WidgetsBinding.instance.platformDispatcher.views.first.physicalSize;
    final orientation = size.width > size.height
        ? Orientation.landscape
        : Orientation.portrait;

    // 避免重复记录
    if (orientation == _lastOrientation) return;
    _lastOrientation = orientation;

    // 仅记录方向变化，不自动切换全屏
    // 全屏状态由用户手动控制
    logger.d(
      'VideoPlayerPage: 屏幕方向变化 => ${orientation == Orientation.landscape ? "横屏" : "竖屏"}',
    );
  }

  /// 缓存源信息，用于 dispose 时更新缩略图
  Future<void> _cacheSourceInfo() async {
    try {
      // 使用缓存的 connections，避免使用 ref
      final connections = _connections;
      if (connections == null || connections.isEmpty) return;

      final connectedEntry = connections.entries.firstWhere(
        (e) => e.value.status == SourceStatus.connected,
        orElse: () => throw Exception('No connected source'),
      );
      _sourceId = connectedEntry.key;
      _fileSystem = connectedEntry.value.adapter.fileSystem;
      // 缓存视频 URL，用于后续缩略图生成
      _videoUrl = await _fileSystem?.getFileUrl(widget.video.path);
    } on Exception catch (e) {
      logger.w('VideoPlayerPage: 缓存源信息失败', e);
    }
  }

  /// 加载字幕
  ///
  /// 优先从本地数据库缓存获取字幕（毫秒级响应），
  /// 如果缓存中没有则回退到实时文件系统扫描。
  Future<void> _loadSubtitles() async {
    // 使用缓存的 connections，避免使用 ref
    final connections = _connections;
    if (connections == null || connections.isEmpty) return;

    final sourceId = widget.video.sourceId;
    SourceConnection? connection;

    // 优先使用视频的 sourceId 获取连接
    if (sourceId != null) {
      connection = connections[sourceId];
    }

    // 如果没有指定 sourceId 或连接不可用，使用第一个已连接的源
    if (connection == null || connection.status != SourceStatus.connected) {
      SourceConnection? connectedEntry;
      for (final c in connections.values) {
        if (c.status == SourceStatus.connected) {
          connectedEntry = c;
          break;
        }
      }
      // 没有任何已连接的源时静默返回，避免抛出未捕获异常
      if (connectedEntry == null) return;
      connection = connectedEntry;
    }

    final adapter = connection.adapter;
    final effectiveSourceId = sourceId ?? connection.source.id;

    try {
      // 使用新的 getSubtitles 方法：优先从数据库缓存获取
      final subtitles = await SubtitleService().getSubtitles(
        sourceId: effectiveSourceId,
        videoPath: widget.video.path,
        videoName: widget.video.name,
        fileSystem: adapter.fileSystem,
      );

      // 检查 widget 是否仍然挂载
      if (!mounted) return;

      // 使用缓存的 notifier，避免使用 ref
      // 需要 try-catch 因为 autoDispose provider 可能在异步期间被销毁
      try {
        _subtitlesNotifier?.state = subtitles;
      }
      // ignore: avoid_catching_errors
      on StateError {
        // Provider 已被销毁，这是预期的边缘情况
        return;
      }

      // 如果找到字幕，且用户尚未手动选择过字幕，自动加载第一个
      // 避免异步加载完成后覆盖用户已选择的字幕
      if (subtitles.isNotEmpty) {
        // 再次检查 mounted，因为上面的操作可能已触发 dispose
        if (!mounted) return;
        try {
          final currentSubtitle = ref.read(currentSubtitleProvider);
          final currentTranslated = ref.read(
            currentTranslatedSubtitleIdProvider,
          );
          if (currentSubtitle == null && currentTranslated == null) {
            await _playerNotifier?.setSubtitle(subtitles.first);
            logger.i('VideoPlayerPage: 自动加载字幕 ${subtitles.first.name}');
          } else {
            logger.d('VideoPlayerPage: 已有字幕/翻译，跳过自动加载');
          }
        }
        // ignore: avoid_catching_errors
        on StateError {
          // Provider 已被销毁，这是预期的边缘情况
        }
      }
    } on Exception catch (e) {
      logger.e('VideoPlayerPage: 加载字幕失败', e);
    }
  }

  @override
  void dispose() {
    // 移除生命周期观察者
    WidgetsBinding.instance.removeObserver(this);
    _hideControlsTimer?.cancel();
    _mouseExitDebounceTimer?.cancel();
    // 同步停止播放 - 使用缓存的 notifier 引用，避免在 dispose 后使用 ref
    _playerNotifier?.stopSync();
    // 后台更新缩略图（仅对没有刮削封面的视频有效）
    _triggerThumbnailUpdate();
    // 移动设备：恢复初始亮度
    _restoreBrightness();
    // 恢复系统 UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([]);
    // 恢复导航栏可见性（通过 Provider 引用计数，由 MainScaffold 决定实际状态）
    BottomNavVisibilityNotifier.instance?.show();
    super.dispose();
  }

  /// 恢复初始亮度
  void _restoreBrightness() {
    if (!_isMobile || _initialBrightness == null) return;
    // 使用 Future.microtask 在后台执行，不阻塞 dispose
    Future.microtask(() async {
      try {
        await ScreenBrightness.instance.setApplicationScreenBrightness(
          _initialBrightness!,
        );
      } on Exception catch (e) {
        logger.w('VideoPlayerPage: 恢复亮度失败', e);
      }
    });
  }

  /// 调整屏幕亮度（仅移动设备）
  Future<void> _setBrightness(double brightness) async {
    if (!_isMobile) return;
    try {
      await ScreenBrightness.instance.setApplicationScreenBrightness(
        brightness,
      );
    } on Exception catch (e) {
      logger.w('VideoPlayerPage: 设置亮度失败', e);
    }
  }

  /// 后台触发缩略图更新
  ///
  /// 在播放器停止后，异步更新缩略图为当前停止位置的帧
  /// 仅对没有刮削封面（posterUrl 和 thumbnailUrl 都为空）的视频有效
  void _triggerThumbnailUpdate() {
    if (_sourceId == null || _videoUrl == null) {
      logger.d('VideoPlayerPage: 缺少源信息，跳过缩略图更新');
      return;
    }

    // 使用 Future.microtask 在后台执行，不阻塞 dispose
    Future.microtask(() async {
      try {
        await VideoMetadataService().refreshThumbnailOnProgressUpdate(
          sourceId: _sourceId!,
          filePath: widget.video.path,
          videoUrl: _videoUrl!,
          fileSystem: _fileSystem,
        );
      } on Exception catch (e) {
        logger.w('VideoPlayerPage: 后台更新缩略图失败', e);
      }
    });
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (_showControls) {
      _hideControlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _showControls && !_isLocked) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  void _toggleControls() {
    if (_isLocked) {
      // 锁定时只显示锁定按钮
      setState(() => _showControls = !_showControls);
      return;
    }
    // 点击时重置鼠标状态（解决底部弹窗关闭后状态异常的问题）
    if (_isDesktop) {
      _isMouseInVideoArea = true;
    }
    setState(() => _showControls = !_showControls);
    _startHideControlsTimer();
  }

  /// 桌面端：鼠标进入视频区域
  void _onMouseEnter() {
    if (!_isDesktop) return;
    // 取消退出防抖计时器（避免快速进出时的误触发）
    _mouseExitDebounceTimer?.cancel();
    _isMouseInVideoArea = true;
    if (!_showControls && !_isLocked) {
      setState(() => _showControls = true);
    }
    _startHideControlsTimer();
  }

  /// 桌面端：鼠标离开视频区域
  void _onMouseExit() {
    if (!_isDesktop) return;

    // 使用防抖避免快速进出导致的闪烁问题（如底部弹窗关闭后的误触发）
    _mouseExitDebounceTimer?.cancel();
    _mouseExitDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      _isMouseInVideoArea = false;
      // 鼠标离开时隐藏控制栏
      _hideControlsTimer?.cancel();
      if (_showControls && !_isLocked) {
        setState(() => _showControls = false);
      }
    });
  }

  /// 桌面端：鼠标移动时重置隐藏计时器
  void _onMouseMove() {
    if (!_isDesktop || !_isMouseInVideoArea) return;
    // 如果控制栏未显示，则显示
    if (!_showControls && !_isLocked) {
      setState(() => _showControls = true);
    }
    // 重置隐藏计时器
    _startHideControlsTimer();
  }

  /// 处理返回事件
  Future<void> _handleBack() async {
    // 在返回之前先暂停播放器
    logger.i('VideoPlayerPage: 准备返回，先暂停播放器');
    _playerNotifier?.pauseSync();

    // 等待一小段时间确保暂停生效
    await Future<void>.delayed(const Duration(milliseconds: 100));

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _handleDoubleTap(TapDownDetails details) {
    if (_isLocked) return;

    final screenWidth = context.screenWidth;

    if (details.localPosition.dx < screenWidth / 3) {
      // 左侧双击 - 快退
      _playerNotifier?.seekBackward();
      setState(() => _showDoubleTapLeft = true);
    } else if (details.localPosition.dx > screenWidth * 2 / 3) {
      // 右侧双击 - 快进
      _playerNotifier?.seekForward();
      setState(() => _showDoubleTapRight = true);
    } else {
      // 中间双击 - 播放/暂停
      _playerNotifier?.playOrPause();
    }
  }

  /// 根据画面比例模式构建视频组件
  Widget _buildVideoWidget(
    VideoPlayerNotifier playerNotifier,
    VideoController controller,
    AspectRatioMode mode,
    SubtitleStyle subtitleStyle,
  ) {
    final fit = switch (mode) {
      AspectRatioMode.fill => BoxFit.fill,
      AspectRatioMode.contain => BoxFit.contain,
      AspectRatioMode.cover => BoxFit.cover,
      _ => BoxFit.contain,
    };

    if (playerNotifier.isUsingNativePlayer) {
      final nativeVideo = playerNotifier.buildVideoWidget(fit: fit);
      if (mode.ratio != null) {
        return AspectRatio(aspectRatio: mode.ratio!, child: nativeVideo);
      }
      return nativeVideo;
    }

    // 视频组件（禁用内置字幕，使用自定义覆盖层）
    final video = Video(
      controller: controller,
      controls: (state) => const SizedBox.shrink(),
      fit: fit,
      // 禁用内置字幕（因为它只支持底部对齐）
      subtitleViewConfiguration: const SubtitleViewConfiguration(
        visible: false,
      ),
    );

    // 构建自定义字幕覆盖层
    final subtitleOverlay = StreamBuilder<List<String>>(
      stream: controller.player.stream.subtitle,
      builder: (context, snapshot) {
        final subtitleLines = snapshot.data ?? [];
        if (subtitleLines.isEmpty ||
            subtitleLines.every((s) => s.trim().isEmpty)) {
          return const SizedBox.shrink();
        }

        final subtitleText = subtitleLines
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.trim())
            .join('\n');

        // 根据位置设置对齐方式和边距
        final (alignment, padding) = switch (subtitleStyle.position) {
          SubtitlePosition.top => (
            Alignment.topCenter,
            EdgeInsets.only(
              top: subtitleStyle.bottomPadding,
              left: 16,
              right: 16,
            ),
          ),
          SubtitlePosition.center => (
            Alignment.center,
            const EdgeInsets.symmetric(horizontal: 16),
          ),
          SubtitlePosition.bottom => (
            Alignment.bottomCenter,
            EdgeInsets.only(
              bottom: subtitleStyle.bottomPadding,
              left: 16,
              right: 16,
            ),
          ),
        };

        return Align(
          alignment: alignment,
          child: Padding(
            padding: padding,
            child: Text(
              subtitleText,
              style: TextStyle(
                fontSize: subtitleStyle.fontSize,
                color: subtitleStyle.fontColor,
                fontWeight: subtitleStyle.fontWeight,
                // 只有开启背景时才显示背景颜色
                backgroundColor: subtitleStyle.showBackground
                    ? subtitleStyle.backgroundColor
                    : null,
                shadows: subtitleStyle.hasOutline
                    ? [
                        Shadow(
                          color: subtitleStyle.outlineColor,
                          blurRadius: subtitleStyle.outlineWidth,
                          offset: const Offset(1, 1),
                        ),
                        Shadow(
                          color: subtitleStyle.outlineColor,
                          blurRadius: subtitleStyle.outlineWidth,
                          offset: const Offset(-1, -1),
                        ),
                        Shadow(
                          color: subtitleStyle.outlineColor,
                          blurRadius: subtitleStyle.outlineWidth,
                          offset: const Offset(1, -1),
                        ),
                        Shadow(
                          color: subtitleStyle.outlineColor,
                          blurRadius: subtitleStyle.outlineWidth,
                          offset: const Offset(-1, 1),
                        ),
                      ]
                    : null,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        );
      },
    );

    // 组合视频和字幕
    final videoWithSubtitle = Stack(
      children: [
        video,
        Positioned.fill(child: subtitleOverlay),
      ],
    );

    // 如果是固定比例模式，用 AspectRatio 包裹
    if (mode.ratio != null) {
      return AspectRatio(aspectRatio: mode.ratio!, child: videoWithSubtitle);
    }

    return videoWithSubtitle;
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(videoPlayerControllerProvider);
    final playerNotifier = ref.read(videoPlayerControllerProvider.notifier);
    final isFullscreen = playerState.isFullscreen;

    // 全屏模式下隐藏系统 UI 并强制横屏
    if (isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      // 非全屏时允许所有方向，默认竖屏显示
      SystemChrome.setPreferredOrientations([]);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBack();
      },
      child: KeyboardShortcuts(
        shortcuts: _buildKeyboardShortcuts(playerNotifier, playerState),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: MouseRegion(
            onEnter: (_) => _onMouseEnter(),
            onExit: (_) => _onMouseExit(),
            child: Listener(
              onPointerHover: (_) => _onMouseMove(),
              child: VideoGestureController(
                playerState: playerState,
                onTap: _toggleControls,
                onDoubleTap: _handleDoubleTap,
                onVolumeChange: _isMobile
                    ? (volume) {
                        playerNotifier.setVolume(volume);
                        _startHideControlsTimer();
                      }
                    : (_) {}, // 桌面端禁用手势音量控制
                onBrightnessChange: _isMobile ? _setBrightness : null,
                onSeek: (position) {
                  playerNotifier.seek(position);
                  _startHideControlsTimer();
                },
                child: Stack(
                  children: [
                    // 视频画面
                    Center(
                      child: Consumer(
                        builder: (context, ref, _) {
                          final aspectMode = ref.watch(aspectRatioModeProvider);
                          final subtitleStyle = ref.watch(
                            subtitleStyleProvider,
                          );

                          // 监听字幕延时变化并应用到播放器
                          ref.listen<SubtitleStyle>(subtitleStyleProvider, (
                            previous,
                            next,
                          ) {
                            if (previous?.delay != next.delay) {
                              AppError.fireAndForget(
                                playerNotifier.setSubtitleDelay(next.delay),
                                action: 'videoPlayer.updateSubtitleDelay',
                              );
                            }
                          });

                          return _buildVideoWidget(
                            playerNotifier,
                            playerNotifier.videoController,
                            aspectMode,
                            subtitleStyle,
                          );
                        },
                      ),
                    ),

                    // 缓冲指示器
                    if (playerState.isBuffering)
                      const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),

                    // 双击快退动画
                    if (_showDoubleTapLeft)
                      Positioned(
                        left: 48,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: DoubleTapSeekOverlay(
                            isForward: false,
                            seekInterval: ref
                                .read(playbackSettingsProvider)
                                .seekInterval,
                            onComplete: () {
                              if (mounted) {
                                setState(() => _showDoubleTapLeft = false);
                              }
                            },
                          ),
                        ),
                      ),

                    // 双击快进动画
                    if (_showDoubleTapRight)
                      Positioned(
                        right: 48,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: DoubleTapSeekOverlay(
                            isForward: true,
                            seekInterval: ref
                                .read(playbackSettingsProvider)
                                .seekInterval,
                            onComplete: () {
                              if (mounted) {
                                setState(() => _showDoubleTapRight = false);
                              }
                            },
                          ),
                        ),
                      ),

                    // 控制层
                    if (_showControls && !_isLocked)
                      Consumer(
                        builder: (context, ref, _) {
                          final subtitles = ref.watch(
                            availableSubtitlesProvider,
                          );
                          final currentSubtitle = ref.watch(
                            currentSubtitleProvider,
                          );
                          final playlist = ref.watch(playlistProvider);
                          final hasPlaylist = playlist.items.length > 1;
                          final playbackSettings = ref.watch(
                            playbackSettingsProvider,
                          );

                          return VideoControls(
                            video: widget.video,
                            state: playerState,
                            seekInterval: playbackSettings.seekInterval,
                            hasSubtitles:
                                subtitles.isNotEmpty || currentSubtitle != null,
                            hasPlaylist: hasPlaylist,
                            hasPrevious: playlist.hasPrevious,
                            hasNext: playlist.hasNext,
                            onPlayPause: () {
                              playerNotifier.playOrPause();
                              _startHideControlsTimer();
                            },
                            onSeek: (position) {
                              playerNotifier.seek(position);
                              _startHideControlsTimer();
                            },
                            onSeekForward: () {
                              playerNotifier.seekForward();
                              _startHideControlsTimer();
                            },
                            onSeekBackward: () {
                              playerNotifier.seekBackward();
                              _startHideControlsTimer();
                            },
                            onVolumeChange: (volume) {
                              playerNotifier.setVolume(volume);
                              _startHideControlsTimer();
                            },
                            onSpeedChange: (speed) {
                              playerNotifier.setSpeed(speed);
                              _startHideControlsTimer();
                            },
                            onToggleFullscreen: playerNotifier.toggleFullscreen,
                            onBack: _handleBack,
                            onPlayPrevious: () {
                              playerNotifier.playPrevious();
                              _startHideControlsTimer();
                            },
                            onPlayNext: () {
                              playerNotifier.playNext();
                              _startHideControlsTimer();
                            },
                            onShowBookmarks: () {
                              showBookmarkSheet(
                                context,
                                videoPath: widget.video.path,
                                videoName: widget.video.name,
                                currentPosition: playerState.position,
                                onSeek: (position) {
                                  playerNotifier.seek(position);
                                  _startHideControlsTimer();
                                },
                              );
                            },
                            isPipSupported: _isPipSupported,
                            onTogglePip: () {
                              playerNotifier.togglePictureInPicture();
                              _startHideControlsTimer();
                            },
                          );
                        },
                      ),

                    // 右下角悬浮按钮区域（画中画 + 锁定）
                    if (_showControls)
                      Positioned(
                        right: 16,
                        bottom: 100,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 画中画按钮（仅在支持时显示）
                            if (_isPipSupported)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: IconButton(
                                    onPressed: () {
                                      playerNotifier.togglePictureInPicture();
                                      _startHideControlsTimer();
                                    },
                                    icon: Icon(
                                      playerState.isPictureInPicture
                                          ? Icons.picture_in_picture_alt
                                          : Icons.picture_in_picture,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                    tooltip: playerState.isPictureInPicture
                                        ? context.l10n.videoPlayerPipExit
                                        : context.l10n.videoPlayerPipEnter,
                                  ),
                                ),
                              ),
                            // 缓存按钮
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _buildCacheButton(),
                            ),
                            // 锁定按钮
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: IconButton(
                                onPressed: () {
                                  setState(() => _isLocked = !_isLocked);
                                  _startHideControlsTimer();
                                },
                                icon: Icon(
                                  _isLocked
                                      ? Icons.lock_rounded
                                      : Icons.lock_open_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                tooltip: _isLocked
                                    ? context.l10n.videoPlayerUnlock
                                    : context.l10n.videoPlayerLock,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // 锁定状态提示
                    if (_isLocked && _showControls)
                      Positioned(
                        bottom: 100,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              context.l10n.videoPlayerScreenLocked,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),

                    // 错误提示
                    if (playerState.errorMessage != null)
                      Center(
                        child: Container(
                          padding: AppSpacing.paddingLg,
                          margin: AppSpacing.paddingLg,
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: AppRadius.borderRadiusMd,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: AppColors.error,
                                size: 48,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                context.l10n.videoPlayerPlaybackFailed,
                                style: context.textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                playerState.errorMessage!,
                                style: context.textTheme.bodySmall?.copyWith(
                                  color: Colors.white70,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: () =>
                                    playerNotifier.play(widget.video),
                                child: Text(context.l10n.videoPlayerRetry),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建键盘快捷键映射
  Map<ShortcutKey, VoidCallback> _buildKeyboardShortcuts(
    VideoPlayerNotifier playerNotifier,
    VideoPlayerState playerState,
  ) {
    if (_isLocked) {
      // 锁定状态下只允许解锁
      return {CommonShortcuts.escape: () => setState(() => _isLocked = false)};
    }

    return {
      // 播放/暂停
      CommonShortcuts.playPause: () {
        playerNotifier.playOrPause();
        _startHideControlsTimer();
      },
      CommonShortcuts.playPauseK: () {
        playerNotifier.playOrPause();
        _startHideControlsTimer();
      },

      // 快进/快退 (左右箭头 - 5秒)
      CommonShortcuts.previous: () {
        playerNotifier.seekBackward();
        _startHideControlsTimer();
      },
      CommonShortcuts.next: () {
        playerNotifier.seekForward();
        _startHideControlsTimer();
      },

      // 快进/快退 (J/L - YouTube风格 10秒)
      CommonShortcuts.seekBackward: () {
        playerNotifier.seekBackward();
        _startHideControlsTimer();
      },
      CommonShortcuts.seekForward: () {
        playerNotifier.seekForward();
        _startHideControlsTimer();
      },

      // 音量调整
      CommonShortcuts.volumeUp: () {
        final newVolume = (playerState.volume + 0.1).clamp(0.0, 2.0);
        playerNotifier.setVolume(newVolume);
        _startHideControlsTimer();
      },
      CommonShortcuts.volumeDown: () {
        final newVolume = (playerState.volume - 0.1).clamp(0.0, 2.0);
        playerNotifier.setVolume(newVolume);
        _startHideControlsTimer();
      },
      CommonShortcuts.mute: () {
        if (playerState.volume > 0) {
          playerNotifier.setVolume(0);
        } else {
          playerNotifier.setVolume(1.0);
        }
        _startHideControlsTimer();
      },

      // 全屏切换
      CommonShortcuts.fullscreen: playerNotifier.toggleFullscreen,
      CommonShortcuts.fullscreenF11: playerNotifier.toggleFullscreen,

      // 显示/隐藏控制栏
      CommonShortcuts.toggleControls: _toggleControls,

      // 退出
      CommonShortcuts.escape: () {
        if (playerState.isFullscreen) {
          playerNotifier.toggleFullscreen();
        } else {
          _handleBack();
        }
      },

      // 播放速度
      CommonShortcuts.speedUp: () {
        final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
        final currentIndex = speeds.indexOf(playerState.speed);
        if (currentIndex < speeds.length - 1) {
          playerNotifier.setSpeed(speeds[currentIndex + 1]);
        }
        _startHideControlsTimer();
      },
      CommonShortcuts.speedDown: () {
        final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
        final currentIndex = speeds.indexOf(playerState.speed);
        if (currentIndex > 0) {
          playerNotifier.setSpeed(speeds[currentIndex - 1]);
        }
        _startHideControlsTimer();
      },
      CommonShortcuts.speedNormal: () {
        playerNotifier.setSpeed(1.0);
        _startHideControlsTimer();
      },

      // 数字键跳转 (0-9 跳转到 0%-90%)
      CommonShortcuts.jumpTo0: () =>
          _seekToPercent(playerNotifier, playerState, 0),
      CommonShortcuts.jumpTo10: () =>
          _seekToPercent(playerNotifier, playerState, 10),
      CommonShortcuts.jumpTo20: () =>
          _seekToPercent(playerNotifier, playerState, 20),
      CommonShortcuts.jumpTo30: () =>
          _seekToPercent(playerNotifier, playerState, 30),
      CommonShortcuts.jumpTo40: () =>
          _seekToPercent(playerNotifier, playerState, 40),
      CommonShortcuts.jumpTo50: () =>
          _seekToPercent(playerNotifier, playerState, 50),
      CommonShortcuts.jumpTo60: () =>
          _seekToPercent(playerNotifier, playerState, 60),
      CommonShortcuts.jumpTo70: () =>
          _seekToPercent(playerNotifier, playerState, 70),
      CommonShortcuts.jumpTo80: () =>
          _seekToPercent(playerNotifier, playerState, 80),
      CommonShortcuts.jumpTo90: () =>
          _seekToPercent(playerNotifier, playerState, 90),

      // 帮助
      CommonShortcuts.help: _showKeyboardHelp,
    };
  }

  /// 跳转到指定百分比位置
  void _seekToPercent(
    VideoPlayerNotifier playerNotifier,
    VideoPlayerState playerState,
    int percent,
  ) {
    final position = Duration(
      milliseconds: (playerState.duration.inMilliseconds * percent / 100)
          .toInt(),
    );
    playerNotifier.seek(position);
    _startHideControlsTimer();
  }

  /// 显示键盘快捷键帮助
  void _showKeyboardHelp() {
    KeyboardShortcutsHelpDialog.show(
      context,
      title: context.l10n.videoPlayerKeyboardHelpTitle,
      shortcuts: [
        (
          key: 'Space / K',
          description: context.l10n.videoPlayerShortcutPlayPause,
        ),
        (
          key: '← / J',
          description: context.l10n.videoPlayerShortcutSeekBackward,
        ),
        (
          key: '→ / L',
          description: context.l10n.videoPlayerShortcutSeekForward,
        ),
        (key: '↑', description: context.l10n.videoPlayerShortcutVolumeUp),
        (key: '↓', description: context.l10n.videoPlayerShortcutVolumeDown),
        (key: 'M', description: context.l10n.videoPlayerShortcutMute),
        (
          key: 'F / F11',
          description: context.l10n.videoPlayerShortcutToggleFullscreen,
        ),
        (key: 'C', description: context.l10n.videoPlayerShortcutToggleControls),
        (key: '[', description: context.l10n.videoPlayerShortcutSpeedDown),
        (key: ']', description: context.l10n.videoPlayerShortcutSpeedUp),
        (key: r'\', description: context.l10n.videoPlayerShortcutSpeedNormal),
        (
          key: '0-9',
          description: context.l10n.videoPlayerShortcutJumpToPercent,
        ),
        (key: 'Esc', description: context.l10n.videoPlayerShortcutExit),
        (key: '?', description: context.l10n.videoPlayerShortcutHelp),
      ],
    );
  }

  /// 构建缓存按钮
  Widget _buildCacheButton() {
    final sourceId = widget.video.sourceId;

    // 如果没有 sourceId，不显示缓存按钮
    if (sourceId == null) {
      return const SizedBox.shrink();
    }

    final isCachedAsync = ref.watch(
      isCachedProvider((sourceId: sourceId, sourcePath: widget.video.path)),
    );

    return isCachedAsync.when(
      data: (isCached) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(24),
        ),
        child: IconButton(
          onPressed: isCached ? null : _handleCacheVideo,
          icon: Icon(
            isCached ? Icons.download_done_rounded : Icons.download_rounded,
            color: isCached ? AppColors.success : Colors.white,
            size: 24,
          ),
          tooltip: isCached
              ? context.l10n.videoPlayerCacheCached
              : context.l10n.videoPlayerCacheVideo,
        ),
      ),
      loading: () => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
        ),
      ),
      error: (e, st) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(24),
        ),
        child: IconButton(
          onPressed: _handleCacheVideo,
          icon: const Icon(
            Icons.download_rounded,
            color: Colors.white,
            size: 24,
          ),
          tooltip: context.l10n.videoPlayerCacheVideo,
        ),
      ),
    );
  }

  /// 处理缓存视频
  Future<void> _handleCacheVideo() async {
    final video = widget.video;
    final sourceId = video.sourceId;

    // 需要 sourceId 才能缓存
    if (sourceId == null) return;

    final notifier = ref.read(transferTasksProvider.notifier);

    final task = await notifier.addCacheTask(
      sourceId: sourceId,
      sourcePath: video.path,
      mediaType: MediaType.video,
      fileSize: video.size,
      thumbnailPath: video.thumbnailUrl,
    );

    if (task != null && mounted) {
      context.showSnackBar(
        context.l10n.videoPlayerCacheAdded,
        action: SnackBarAction(
          label: context.l10n.videoPlayerCacheView,
          onPressed: () => showTransferCache(context),
        ),
      );
    }
  }
}
