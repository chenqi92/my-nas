import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/cast/cast_service.dart';
import 'package:my_nas/features/video/domain/entities/cast_device.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 投屏状态
class CastState {
  const CastState({
    this.isDiscovering = false,
    this.devices = const [],
    this.session,
    this.error,
  });

  /// 是否正在搜索设备
  final bool isDiscovering;

  /// 发现的设备列表
  final List<CastDevice> devices;

  /// 当前投屏会话
  final CastSession? session;

  /// 错误信息
  final String? error;

  /// 是否正在投屏
  bool get isCasting => session != null;

  /// 是否正在播放
  bool get isPlaying => session?.isPlaying ?? false;

  /// 是否暂停
  bool get isPaused => session?.isPaused ?? false;

  /// 是否加载中
  bool get isLoading => session?.isLoading ?? false;

  CastState copyWith({
    bool? isDiscovering,
    List<CastDevice>? devices,
    CastSession? session,
    String? error,
    bool clearSession = false,
    bool clearError = false,
  }) =>
      CastState(
        isDiscovering: isDiscovering ?? this.isDiscovering,
        devices: devices ?? this.devices,
        session: clearSession ? null : (session ?? this.session),
        error: clearError ? null : (error ?? this.error),
      );
}

/// 投屏状态管理器
class CastNotifier extends StateNotifier<CastState> {
  CastNotifier({CastService? castService})
      : _castService = castService ?? CastService(),
        super(const CastState()) {
    _init();
  }

  final CastService _castService;

  /// 设备流订阅
  StreamSubscription<List<CastDevice>>? _deviceSubscription;

  /// 会话流订阅
  StreamSubscription<CastSession?>? _sessionSubscription;

  /// 初始化
  void _init() {
    // 监听设备发现
    _deviceSubscription = _castService.deviceStream.listen((devices) {
      state = state.copyWith(devices: devices);
    });

    // 监听会话变化
    _sessionSubscription = _castService.sessionStream.listen((session) {
      state = state.copyWith(
        session: session,
        clearSession: session == null,
      );
    });
  }

  /// 开始设备发现
  Future<void> startDiscovery({Duration timeout = const Duration(seconds: 15)}) async {
    if (state.isDiscovering) return;

    state = state.copyWith(isDiscovering: true, clearError: true);

    try {
      await _castService.startDiscovery(timeout: timeout);
    } catch (e, st) {
      AppError.handle(e, st, 'castStartDiscovery');
      state = state.copyWith(error: appL10n.castStartDiscoveryFailed);
    } finally {
      state = state.copyWith(isDiscovering: false);
    }
  }

  /// 停止设备发现
  void stopDiscovery() {
    _castService.stopDiscovery();
    state = state.copyWith(isDiscovering: false);
  }

  /// 刷新设备列表
  Future<void> refreshDevices() async {
    state = state.copyWith(devices: []);
    await startDiscovery();
  }

  /// 开始投屏
  Future<bool> cast({
    required CastDevice device,
    required String videoPath,
    required String videoTitle,
    required NasFileSystem fileSystem,
    String? subtitlePath,
    Duration? startPosition,
    int? fileSize,
  }) async {
    state = state.copyWith(clearError: true);

    try {
      logger.i('开始投屏: $videoTitle -> ${device.name}');

      final session = await _castService.cast(
        device: device,
        videoPath: videoPath,
        videoTitle: videoTitle,
        fileSystem: fileSystem,
        subtitlePath: subtitlePath,
        startPosition: startPosition,
        fileSize: fileSize,
      );

      if (session == null) {
        state = state.copyWith(error: appL10n.castFailedNull);
        return false;
      }

      return true;
    } catch (e, st) {
      AppError.handle(e, st, 'castStart', {
        'device': device.name,
        'video': videoPath,
      });
      state = state.copyWith(error: appL10n.castFailedWithError(e));
      return false;
    }
  }

  /// 播放
  Future<void> play() async {
    try {
      await _castService.play();
    } catch (e, st) {
      AppError.handle(e, st, 'castPlay');
    }
  }

  /// 暂停
  Future<void> pause() async {
    try {
      await _castService.pause();
    } catch (e, st) {
      AppError.handle(e, st, 'castPause');
    }
  }

  /// 停止投屏
  Future<void> stop() async {
    try {
      await _castService.stop();
      state = state.copyWith(clearSession: true);
    } catch (e, st) {
      AppError.handle(e, st, 'castStop');
    }
  }

  /// 跳转
  Future<void> seek(Duration position) async {
    try {
      await _castService.seek(position);
    } catch (e, st) {
      AppError.handle(e, st, 'castSeek');
    }
  }

  /// 设置音量
  Future<void> setVolume(double volume) async {
    try {
      await _castService.setVolume(volume);
    } catch (e, st) {
      AppError.handle(e, st, 'castSetVolume');
    }
  }

  /// 切换播放/暂停
  Future<void> togglePlayPause() async {
    if (state.isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  /// 清除错误
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// 尝试恢复投屏连接
  ///
  /// 当投屏连接断开时调用此方法尝试恢复
  Future<bool> tryReconnect() async {
    if (!state.isCasting) return false;

    try {
      final success = await _castService.tryReconnect();
      if (!success) {
        state = state.copyWith(error: appL10n.castReconnectFailed);
      }
      return success;
    } catch (e, st) {
      AppError.handle(e, st, 'castTryReconnect');
      state = state.copyWith(error: appL10n.castReconnectFailedWithError(e));
      return false;
    }
  }

  /// 检查是否连接断开
  bool get isDisconnected =>
      state.session?.playbackState == CastPlaybackState.error;

  @override
  void dispose() {
    _deviceSubscription?.cancel();
    _sessionSubscription?.cancel();
    // 使用 fireAndForget 处理异步 dispose，确保异常被捕获
    AppError.fireAndForget(_castService.dispose(), action: 'castServiceDispose');
    super.dispose();
  }
}

/// 投屏状态 Provider
final castProvider = StateNotifierProvider<CastNotifier, CastState>((ref) => CastNotifier());

/// 是否正在投屏
final isCastingProvider = Provider<bool>(
  (ref) => ref.watch(castProvider.select((state) => state.isCasting)),
);

/// 当前投屏设备
final castDeviceProvider = Provider<CastDevice?>(
  (ref) => ref.watch(castProvider.select((state) => state.session?.device)),
);

/// 投屏播放状态
final castPlaybackStateProvider = Provider<CastPlaybackState>(
  (ref) => ref.watch(
    castProvider.select((state) => state.session?.playbackState ?? CastPlaybackState.idle),
  ),
);

/// 投屏播放进度
final castPositionProvider = Provider<Duration>(
  (ref) => ref.watch(
    castProvider.select((state) => state.session?.position ?? Duration.zero),
  ),
);

/// 投屏视频时长
final castDurationProvider = Provider<Duration>(
  (ref) => ref.watch(
    castProvider.select((state) => state.session?.duration ?? Duration.zero),
  ),
);

/// 投屏音量
final castVolumeProvider = Provider<double>(
  (ref) => ref.watch(castProvider.select((state) => state.session?.volume ?? 1.0)),
);

/// 发现的设备列表
final castDevicesProvider = Provider<List<CastDevice>>(
  (ref) => ref.watch(castProvider.select((state) => state.devices)),
);

/// 是否正在搜索设备
final isDiscoveringDevicesProvider = Provider<bool>(
  (ref) => ref.watch(castProvider.select((state) => state.isDiscovering)),
);

/// 投屏是否断开连接
final isCastDisconnectedProvider = Provider<bool>(
  (ref) => ref.watch(
    castProvider.select((state) => state.session?.playbackState == CastPlaybackState.error),
  ),
);

/// 投屏错误信息
final castErrorProvider = Provider<String?>(
  (ref) => ref.watch(castProvider.select((state) => state.error ?? state.session?.errorMessage)),
);
