import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/domain/entities/cast_device.dart';

/// AirPlay 协议适配器
/// 负责 AirPlay 设备发现和媒体投屏控制
class AirPlayAdapter {
  AirPlayAdapter();

  /// Bonjour 发现实例
  BonsoirDiscovery? _discovery;

  /// 是否正在搜索
  bool _isSearching = false;

  /// 当前设备缓存
  final Map<String, _AirPlayDevice> _devices = {};

  /// 当前连接的设备
  _AirPlayDevice? _currentDevice;

  /// HTTP 客户端
  HttpClient? _httpClient;

  /// 播放信息缓存
  _PlaybackInfo? _cachedPlaybackInfo;

  /// 缓存时间
  DateTime? _playbackInfoCachedAt;

  /// 缓存有效期（800ms，确保在1秒轮询周期内有效）
  static const _playbackInfoCacheDuration = Duration(milliseconds: 800);

  /// 设备发现控制器
  final _deviceController = StreamController<List<CastDevice>>.broadcast();

  /// 事件流订阅
  StreamSubscription<BonsoirDiscoveryEvent>? _eventSubscription;

  /// 设备发现流
  Stream<List<CastDevice>> get deviceStream => _deviceController.stream;

  /// 是否正在投屏
  bool get isCasting => _currentDevice != null;

  /// 开始设备发现
  Future<void> startDiscovery({Duration timeout = const Duration(seconds: 10)}) async {
    if (_isSearching) {
      logger.i('AirPlay 设备搜索已在进行中');
      return;
    }

    _isSearching = true;
    _devices.clear();

    try {
      logger.i('开始搜索 AirPlay 设备...');

      // 创建 Bonjour 发现实例
      _discovery = BonsoirDiscovery(type: '_airplay._tcp');

      // 初始化
      await _discovery!.initialize();

      // 监听发现事件
      _eventSubscription = _discovery!.eventStream?.listen(_handleDiscoveryEvent);

      // 开始搜索
      await _discovery!.start();

      // 设置超时
      Timer(timeout, () {
        if (_isSearching) {
          stopDiscovery();
        }
      });
    } catch (e, st) {
      AppError.handle(e, st, 'airplayStartDiscovery');
      _isSearching = false;
    }
  }

  /// 处理发现事件
  void _handleDiscoveryEvent(BonsoirDiscoveryEvent event) {
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent():
        logger.i('发现 AirPlay 服务: ${event.service.name}');
        // 服务发现后需要解析
        _discovery?.serviceResolver.resolveService(event.service);
      case BonsoirDiscoveryServiceResolvedEvent():
        _addDevice(event.service);
      case BonsoirDiscoveryServiceLostEvent():
        _removeDevice(event.service.name);
      default:
        break;
    }
  }

  /// 添加设备
  void _addDevice(BonsoirService service) {
    final host = service.host;
    if (host == null || host.isEmpty) return;

    final device = _AirPlayDevice(
      name: service.name,
      host: host,
      port: service.port,
      attributes: service.attributes,
    );

    logger.i('解析 AirPlay 设备: ${device.name} @ ${device.host}:${device.port}');
    _devices[device.name] = device;
    _deviceController.add(_convertToCastDevices());
  }

  /// 移除设备
  void _removeDevice(String name) {
    if (_devices.remove(name) != null) {
      logger.i('AirPlay 设备离线: $name');
      _deviceController.add(_convertToCastDevices());
    }
  }

  /// 停止设备发现
  Future<void> stopDiscovery() async {
    _isSearching = false;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _discovery?.stop();
    _discovery = null;
    logger.i('停止 AirPlay 设备搜索');
  }

  /// 获取当前发现的设备列表
  List<CastDevice> getDiscoveredDevices() => _convertToCastDevices();

  /// 转换为 CastDevice 列表
  List<CastDevice> _convertToCastDevices() => _devices.values
      .map(
        (device) => CastDevice(
          id: device.name,
          name: device.name,
          protocol: CastProtocol.airplay,
          address: device.host,
          port: device.port,
        ),
      )
      .toList();

  /// 投屏视频
  Future<bool> castVideo({
    required String deviceId,
    required String videoUrl,
    required String title,
    String? subtitleUrl,
    Duration? startPosition,
  }) async {
    final device = _devices[deviceId];
    if (device == null) {
      throw Exception('设备未找到: $deviceId');
    }

    try {
      _currentDevice = device;
      _httpClient = HttpClient()..connectionTimeout = const Duration(seconds: 10);

      logger
        ..i('开始 AirPlay 投屏到 ${device.name}')
        ..i('视频URL: $videoUrl');

      // 构建播放请求
      final startPositionSeconds = (startPosition?.inMilliseconds ?? 0) / 1000.0;

      // 发送 /play 请求
      final request = await _httpClient!.postUrl(
        Uri.parse('http://${device.host}:${device.port}/play'),
      );

      request.headers.set('Content-Type', 'text/parameters');
      request.headers.set('User-Agent', 'MediaControl/1.0');

      // AirPlay 播放参数
      final body = 'Content-Location: $videoUrl\n'
          'Start-Position: $startPositionSeconds\n';

      request.write(body);

      final response = await request.close();
      final success = response.statusCode == 200;

      if (success) {
        logger.i('AirPlay 投屏成功');
      } else {
        logger.e('AirPlay 投屏失败: ${response.statusCode}');
      }

      return success;
    } catch (e, st) {
      AppError.handle(e, st, 'airplayCastVideo', {'deviceId': deviceId, 'videoUrl': videoUrl});
      _currentDevice = null;
      return false;
    }
  }

  /// 播放
  Future<void> play() async {
    if (_currentDevice == null || _httpClient == null) return;

    try {
      final request = await _httpClient!.postUrl(
        Uri.parse('http://${_currentDevice!.host}:${_currentDevice!.port}/rate?value=1'),
      );
      await request.close();
    } catch (e, st) {
      AppError.handle(e, st, 'airplayPlay');
    }
  }

  /// 暂停
  Future<void> pause() async {
    if (_currentDevice == null || _httpClient == null) return;

    try {
      final request = await _httpClient!.postUrl(
        Uri.parse('http://${_currentDevice!.host}:${_currentDevice!.port}/rate?value=0'),
      );
      await request.close();
    } catch (e, st) {
      AppError.handle(e, st, 'airplayPause');
    }
  }

  /// 停止
  Future<void> stop() async {
    if (_currentDevice == null || _httpClient == null) return;

    try {
      final request = await _httpClient!.postUrl(
        Uri.parse('http://${_currentDevice!.host}:${_currentDevice!.port}/stop'),
      );
      await request.close();
    } catch (e, st) {
      AppError.handle(e, st, 'airplayStop');
    } finally {
      _currentDevice = null;
      _clearPlaybackInfoCache();
    }
  }

  /// 跳转到指定位置
  Future<void> seek(Duration position) async {
    if (_currentDevice == null || _httpClient == null) return;

    try {
      final positionSeconds = position.inMilliseconds / 1000.0;
      final request = await _httpClient!.postUrl(
        Uri.parse('http://${_currentDevice!.host}:${_currentDevice!.port}/scrub?position=$positionSeconds'),
      );
      await request.close();
    } catch (e, st) {
      AppError.handle(e, st, 'airplaySeek');
    }
  }

  /// 设置音量（AirPlay 音量通过系统控制，这里仅作兼容）
  Future<void> setVolume(int volume) async {
    // AirPlay 音量通常由接收设备控制
    // 部分设备支持 /volume 端点
    if (_currentDevice == null || _httpClient == null) return;

    try {
      final request = await _httpClient!.postUrl(
        Uri.parse('http://${_currentDevice!.host}:${_currentDevice!.port}/volume?value=${volume / 100}'),
      );
      await request.close();
    } catch (e, st) {
      AppError.ignore(e, st, 'AirPlay 音量控制可能不受支持');
    }
  }

  /// 获取播放信息（带缓存）
  ///
  /// 使用缓存避免在同一轮询周期内多次请求
  Future<_PlaybackInfo?> _getPlaybackInfo({bool forceRefresh = false}) async {
    if (_currentDevice == null || _httpClient == null) return null;

    // 检查缓存是否有效
    final isCacheValid = !forceRefresh &&
        _cachedPlaybackInfo != null &&
        _playbackInfoCachedAt != null &&
        DateTime.now().difference(_playbackInfoCachedAt!) < _playbackInfoCacheDuration;

    if (isCacheValid) {
      return _cachedPlaybackInfo;
    }

    try {
      final request = await _httpClient!.getUrl(
        Uri.parse('http://${_currentDevice!.host}:${_currentDevice!.port}/playback-info'),
      );
      final response = await request.close();

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final info = _parsePlaybackInfo(body);
        // 更新缓存
        _cachedPlaybackInfo = info;
        _playbackInfoCachedAt = DateTime.now();
        return info;
      }
    } catch (e, st) {
      AppError.ignore(e, st, '获取 AirPlay 播放信息失败');
    }
    return null;
  }

  /// 清除播放信息缓存
  void _clearPlaybackInfoCache() {
    _cachedPlaybackInfo = null;
    _playbackInfoCachedAt = null;
  }

  /// 解析播放信息（plist 格式简化解析）
  _PlaybackInfo? _parsePlaybackInfo(String plistContent) {
    try {
      // 简化解析 plist XML
      double? position;
      double? duration;
      double? rate;

      // 解析 position
      final positionMatch = RegExp(r'<key>position</key>\s*<real>([^<]+)</real>').firstMatch(plistContent);
      if (positionMatch != null) {
        position = double.tryParse(positionMatch.group(1) ?? '');
      }

      // 解析 duration
      final durationMatch = RegExp(r'<key>duration</key>\s*<real>([^<]+)</real>').firstMatch(plistContent);
      if (durationMatch != null) {
        duration = double.tryParse(durationMatch.group(1) ?? '');
      }

      // 解析 rate（播放速率，0=暂停，1=播放）
      final rateMatch = RegExp(r'<key>rate</key>\s*<real>([^<]+)</real>').firstMatch(plistContent);
      if (rateMatch != null) {
        rate = double.tryParse(rateMatch.group(1) ?? '');
      }

      return _PlaybackInfo(
        position: position != null ? Duration(milliseconds: (position * 1000).round()) : null,
        duration: duration != null ? Duration(milliseconds: (duration * 1000).round()) : null,
        isPlaying: (rate ?? 0) > 0,
      );
    } catch (e) {
      return null;
    }
  }

  /// 获取当前播放位置
  Future<Duration?> getPosition() async {
    final info = await _getPlaybackInfo();
    return info?.position;
  }

  /// 获取播放时长
  Future<Duration?> getDuration() async {
    final info = await _getPlaybackInfo();
    return info?.duration;
  }

  /// 获取播放状态
  Future<CastPlaybackState> getPlaybackState() async {
    final info = await _getPlaybackInfo();
    if (info == null) return CastPlaybackState.idle;
    return info.isPlaying ? CastPlaybackState.playing : CastPlaybackState.paused;
  }

  /// 释放资源
  Future<void> dispose() async {
    await stopDiscovery();
    await stop();
    _httpClient?.close(force: true);
    _httpClient = null;
    _clearPlaybackInfoCache();
    await _deviceController.close();
    _devices.clear();
  }
}

/// AirPlay 设备信息
class _AirPlayDevice {
  _AirPlayDevice({
    required this.name,
    required this.host,
    required this.port,
    this.attributes = const {},
  });

  final String name;
  final String host;
  final int port;
  final Map<String, String> attributes;
}

/// 播放信息
class _PlaybackInfo {
  _PlaybackInfo({
    this.position,
    this.duration,
    this.isPlaying = false,
  });

  final Duration? position;
  final Duration? duration;
  final bool isPlaying;
}
