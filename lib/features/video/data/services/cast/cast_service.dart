import 'dart:async';

import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/cast/adapters/airplay_adapter.dart';
import 'package:my_nas/features/video/data/services/cast/adapters/dlna_adapter.dart';
import 'package:my_nas/features/video/data/services/cast/cast_media_proxy_server.dart';
import 'package:my_nas/features/video/domain/entities/cast_device.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 投屏服务
/// 统一管理 DLNA 和 AirPlay 投屏
class CastService {
  CastService({
    CastMediaProxyServer? proxyServer,
    DlnaAdapter? dlnaAdapter,
    AirPlayAdapter? airplayAdapter,
  }) : _proxyServer = proxyServer ?? CastMediaProxyServer(),
       _dlnaAdapter = dlnaAdapter ?? DlnaAdapter(),
       _airplayAdapter = airplayAdapter ?? AirPlayAdapter() {
    _initDeviceStreams();
  }

  final CastMediaProxyServer _proxyServer;
  final DlnaAdapter _dlnaAdapter;
  final AirPlayAdapter _airplayAdapter;

  /// 当前投屏会话
  CastSession? _currentSession;

  /// 当前流 token（用于停止时清理）
  String? _currentStreamToken;

  /// 状态更新定时器
  Timer? _statusTimer;

  /// 连续轮询错误计数
  int _pollErrorCount = 0;
  int _operationGeneration = 0;
  bool _pollInFlight = false;
  Future<void> _operationQueue = Future<void>.value();

  /// 最大连续错误次数（超过后认为连接断开）
  static const _maxPollErrors = 5;

  /// 会话状态控制器
  final _sessionController = StreamController<CastSession?>.broadcast();

  /// 合并的设备流控制器
  final _deviceController = StreamController<List<CastDevice>>.broadcast();

  /// 设备流订阅
  StreamSubscription<List<CastDevice>>? _dlnaSubscription;
  StreamSubscription<List<CastDevice>>? _airplaySubscription;

  /// 当前设备缓存
  List<CastDevice> _dlnaDevices = [];
  List<CastDevice> _airplayDevices = [];

  /// 会话状态流
  Stream<CastSession?> get sessionStream => _sessionController.stream;

  /// 获取当前会话
  CastSession? get currentSession => _currentSession;

  /// 是否正在投屏
  bool get isCasting => _currentSession != null;

  /// 设备发现流（合并 DLNA 和 AirPlay）
  Stream<List<CastDevice>> get deviceStream => _deviceController.stream;

  /// 初始化设备流合并
  void _initDeviceStreams() {
    // 监听 DLNA 设备
    _dlnaSubscription = _dlnaAdapter.deviceStream.listen((devices) {
      _dlnaDevices = devices;
      _emitCombinedDevices();
    });

    // 监听 AirPlay 设备
    _airplaySubscription = _airplayAdapter.deviceStream.listen((devices) {
      _airplayDevices = devices;
      _emitCombinedDevices();
    });
  }

  /// 发送合并后的设备列表
  void _emitCombinedDevices() {
    final combined = <CastDevice>[..._dlnaDevices, ..._airplayDevices];
    _deviceController.add(combined);
  }

  /// 开始设备发现
  Future<void> startDiscovery({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    logger.i('开始设备发现');

    // 并行启动 DLNA 和 AirPlay 搜索
    await Future.wait([
      _dlnaAdapter.startDiscovery(timeout: timeout),
      _airplayAdapter.startDiscovery(timeout: timeout),
    ]);
  }

  /// 停止设备发现
  void stopDiscovery() {
    _dlnaAdapter.stopDiscovery();
    _airplayAdapter.stopDiscovery();
  }

  /// 获取当前发现的设备列表
  List<CastDevice> getDiscoveredDevices() {
    final devices = <CastDevice>[
      ..._dlnaAdapter.getDiscoveredDevices(),
      ..._airplayAdapter.getDiscoveredDevices(),
    ];
    return devices;
  }

  /// 投屏视频
  Future<CastSession?> cast({
    required CastDevice device,
    required String videoPath,
    required String videoTitle,
    required NasFileSystem fileSystem,
    String? subtitlePath,
    Duration? startPosition,
    int? fileSize,
  }) {
    final generation = ++_operationGeneration;
    return _enqueueOperation(() async {
      if (generation != _operationGeneration) return null;
      return _castInternal(
        generation: generation,
        device: device,
        videoPath: videoPath,
        videoTitle: videoTitle,
        fileSystem: fileSystem,
        subtitlePath: subtitlePath,
        startPosition: startPosition,
        fileSize: fileSize,
      );
    });
  }

  Future<CastSession?> _castInternal({
    required int generation,
    required CastDevice device,
    required String videoPath,
    required String videoTitle,
    required NasFileSystem fileSystem,
    String? subtitlePath,
    Duration? startPosition,
    int? fileSize,
  }) async {
    String? registeredToken;
    var adapterInvoked = false;
    try {
      // 0. 如果有正在进行的投屏，先停止并清理
      if (_currentSession != null || _currentStreamToken != null) {
        await _stopCurrent();
      }
      if (generation != _operationGeneration) return null;

      // 1. 确保代理服务器运行
      await _proxyServer.ensureRunning();
      if (generation != _operationGeneration) return null;

      // 2. 注册媒体流
      final token = _proxyServer.registerStream(
        path: videoPath,
        fileSystem: fileSystem,
        fileSize: fileSize,
        subtitlePath: subtitlePath,
      );
      registeredToken = token;

      // 保存 token 以便停止时清理
      _currentStreamToken = token;

      // 3. 获取流 URL
      final videoUrl = await _proxyServer.getStreamUrl(token);
      if (generation != _operationGeneration) {
        _unregisterOwnedStream(token);
        return null;
      }
      if (videoUrl == null) {
        _unregisterOwnedStream(token);
        throw Exception(appL10n.castServiceNoLocalIpError);
      }

      final subtitleUrl = await _proxyServer.getSubtitleUrl(token);
      if (generation != _operationGeneration) {
        _unregisterOwnedStream(token);
        return null;
      }

      logger.i('投屏URL: $videoUrl');
      if (subtitleUrl != null) {
        logger.i('字幕URL: $subtitleUrl');
      }

      // 4. 根据协议类型投屏
      bool success;
      adapterInvoked = true;
      switch (device.protocol) {
        case CastProtocol.dlna:
          success = await _dlnaAdapter.castVideo(
            deviceId: device.id,
            videoUrl: videoUrl,
            title: videoTitle,
            subtitleUrl: subtitleUrl,
          );
        case CastProtocol.airplay:
          success = await _airplayAdapter.castVideo(
            deviceId: device.id,
            videoUrl: videoUrl,
            title: videoTitle,
            subtitleUrl: subtitleUrl,
            startPosition: startPosition,
          );
      }

      if (generation != _operationGeneration) {
        if (success) await _stopAdapter(device.protocol);
        _unregisterOwnedStream(token);
        return null;
      }

      if (!success) {
        _unregisterOwnedStream(token);
        return null;
      }

      // 5. 创建会话
      _currentSession = CastSession(
        device: device,
        videoTitle: videoTitle,
        videoPath: videoPath,
        playbackState: CastPlaybackState.loading,
      );

      // 重置错误计数
      _pollErrorCount = 0;

      _sessionController.add(_currentSession);

      // 6. 启动状态轮询
      _startStatusPolling(generation);

      // 7. 跳转到起始位置（DLNA 需要单独处理）
      if (device.protocol == CastProtocol.dlna &&
          startPosition != null &&
          startPosition > Duration.zero) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (generation != _operationGeneration) return null;
        await seek(startPosition);
      }

      return generation == _operationGeneration ? _currentSession : null;
    } catch (e, st) {
      if (generation != _operationGeneration && adapterInvoked) {
        await _stopAdapter(device.protocol);
      }
      if (registeredToken != null) _unregisterOwnedStream(registeredToken);
      AppError.handle(e, st, 'castVideo', {
        'device': device.name,
        'videoPath': videoPath,
      });
      return null;
    }
  }

  /// 播放
  Future<void> play() async {
    if (_currentSession == null) return;

    try {
      switch (_currentSession!.device.protocol) {
        case CastProtocol.dlna:
          await _dlnaAdapter.play();
        case CastProtocol.airplay:
          await _airplayAdapter.play();
      }
    } catch (e, st) {
      AppError.handle(e, st, 'castPlay');
    }
  }

  /// 暂停
  Future<void> pause() async {
    if (_currentSession == null) return;

    try {
      switch (_currentSession!.device.protocol) {
        case CastProtocol.dlna:
          await _dlnaAdapter.pause();
        case CastProtocol.airplay:
          await _airplayAdapter.pause();
      }
    } catch (e, st) {
      AppError.handle(e, st, 'castPause');
    }
  }

  /// 停止投屏
  Future<void> stop() async {
    _operationGeneration++;
    await _enqueueOperation<bool>(() async {
      await _stopCurrent();
      return true;
    });
  }

  Future<void> _stopCurrent() async {
    _stopStatusPolling();

    // 清理流注册
    if (_currentStreamToken != null) {
      _unregisterOwnedStream(_currentStreamToken!);
    }

    if (_currentSession == null) return;

    try {
      switch (_currentSession!.device.protocol) {
        case CastProtocol.dlna:
          await _dlnaAdapter.stop();
        case CastProtocol.airplay:
          await _airplayAdapter.stop();
      }
    } catch (e, st) {
      AppError.handle(e, st, 'castStop');
    } finally {
      _currentSession = null;
      _pollErrorCount = 0;
      _sessionController.add(null);
      logger.i('投屏已停止');
    }
  }

  Future<T> _enqueueOperation<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _operationQueue = _operationQueue.then((_) async {
      try {
        result.complete(await operation());
      } catch (e, st) {
        result.completeError(e, st);
      }
    });
    return result.future;
  }

  void _unregisterOwnedStream(String token) {
    if (_currentStreamToken != token) return;
    _proxyServer.unregisterStream(token);
    _currentStreamToken = null;
  }

  Future<void> _stopAdapter(CastProtocol protocol) async {
    try {
      switch (protocol) {
        case CastProtocol.dlna:
          await _dlnaAdapter.stop();
        case CastProtocol.airplay:
          await _airplayAdapter.stop();
      }
    } catch (e, st) {
      AppError.ignore(e, st, '清理过期投屏会话失败');
    }
  }

  /// 跳转
  Future<void> seek(Duration position) async {
    if (_currentSession == null) return;

    try {
      switch (_currentSession!.device.protocol) {
        case CastProtocol.dlna:
          await _dlnaAdapter.seek(position);
        case CastProtocol.airplay:
          await _airplayAdapter.seek(position);
      }
    } catch (e, st) {
      AppError.handle(e, st, 'castSeek');
    }
  }

  /// 设置音量
  Future<void> setVolume(double volume) async {
    if (_currentSession == null) return;
    final generation = _operationGeneration;
    final session = _currentSession!;

    try {
      final intVolume = (volume * 100).round();
      switch (session.device.protocol) {
        case CastProtocol.dlna:
          await _dlnaAdapter.setVolume(intVolume);
        case CastProtocol.airplay:
          await _airplayAdapter.setVolume(intVolume);
      }

      if (generation != _operationGeneration ||
          !identical(_currentSession, session)) {
        return;
      }
      _currentSession = session.copyWith(volume: volume);
      _sessionController.add(_currentSession);
    } catch (e, st) {
      AppError.handle(e, st, 'castSetVolume');
    }
  }

  /// 启动状态轮询
  void _startStatusPolling(int generation) {
    _stopStatusPolling();
    _statusTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _pollStatus(generation),
    );
  }

  /// 停止状态轮询
  void _stopStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = null;
  }

  /// 尝试恢复投屏连接
  ///
  /// 当状态轮询检测到连接断开后，可以调用此方法尝试恢复
  Future<bool> tryReconnect() async {
    if (_currentSession == null) return false;
    final generation = _operationGeneration;

    logger.i('尝试恢复投屏连接...');

    // 重置错误计数
    _pollErrorCount = 0;

    // 重新启动状态轮询
    _startStatusPolling(generation);

    // 等待一次轮询完成
    await Future<void>.delayed(const Duration(seconds: 2));
    if (generation != _operationGeneration) return false;

    // 检查是否恢复成功
    if (_currentSession?.playbackState == CastPlaybackState.error) {
      logger.w('投屏连接恢复失败');
      return false;
    }

    logger.i('投屏连接已恢复');
    return true;
  }

  /// 轮询状态
  Future<void> _pollStatus(int generation) async {
    if (_pollInFlight ||
        generation != _operationGeneration ||
        _currentSession == null) {
      return;
    }
    _pollInFlight = true;
    final session = _currentSession!;

    try {
      Duration? position;
      Duration? duration;
      CastPlaybackState? state;

      switch (session.device.protocol) {
        case CastProtocol.dlna:
          position = await _dlnaAdapter.getPosition();
          duration = await _dlnaAdapter.getDuration();
          state = await _dlnaAdapter.getPlaybackState();
        case CastProtocol.airplay:
          position = await _airplayAdapter.getPosition();
          duration = await _airplayAdapter.getDuration();
          state = await _airplayAdapter.getPlaybackState();
      }

      if (!_hasValidPollStatus(position, duration, state)) {
        throw StateError('投屏设备未返回有效播放状态');
      }
      if (generation != _operationGeneration ||
          !identical(_currentSession, session)) {
        return;
      }

      // 重置错误计数（成功获取状态）
      _pollErrorCount = 0;

      _currentSession = _currentSession!.copyWith(
        position: position,
        duration: duration,
        playbackState: state,
      );
      _sessionController.add(_currentSession);
    } catch (e, st) {
      if (generation != _operationGeneration ||
          !identical(_currentSession, session)) {
        return;
      }
      _pollErrorCount++;

      if (_pollErrorCount >= _maxPollErrors) {
        // 连续多次失败，认为连接断开
        logger.e('投屏连接可能已断开，连续 $_pollErrorCount 次轮询失败');
        AppError.handle(e, st, 'castPollStatusDisconnected', {
          'errorCount': _pollErrorCount,
        });

        // 更新会话状态为错误
        _currentSession = _currentSession?.copyWith(
          playbackState: CastPlaybackState.error,
          errorMessage: appL10n.castServiceConnectionDisconnected,
        );
        _sessionController.add(_currentSession);

        // 停止轮询但不完全停止投屏（允许用户重试或手动停止）
        _stopStatusPolling();
      } else {
        // 只是偶发错误，记录但不上报
        AppError.ignore(e, st, '投屏状态轮询失败 ($_pollErrorCount/$_maxPollErrors)');
      }
    } finally {
      _pollInFlight = false;
    }
  }

  bool _hasValidPollStatus(
    Duration? position,
    Duration? duration,
    CastPlaybackState? state,
  ) {
    if (state == null) return false;
    if (state != CastPlaybackState.idle) return true;
    return position != null || duration != null;
  }

  /// 释放资源
  Future<void> dispose() async {
    _stopStatusPolling();
    await stop();
    await _proxyServer.stop();
    _dlnaAdapter.dispose();
    await _airplayAdapter.dispose();
    await _dlnaSubscription?.cancel();
    await _airplaySubscription?.cancel();
    await _sessionController.close();
    await _deviceController.close();
  }
}
