import 'dart:async';
import 'dart:convert';

import 'package:dlna_dart/dlna.dart';
import 'package:dlna_dart/xmlParser.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/domain/entities/cast_device.dart';

/// DLNA 协议适配器
/// 负责 DLNA 设备发现和媒体投屏控制
class DlnaAdapter {
  DlnaAdapter();

  /// DLNA 管理器
  DLNAManager? _manager;

  /// 设备管理器
  DeviceManager? _deviceManager;

  /// 是否正在搜索
  bool _isSearching = false;

  /// 当前设备缓存
  final Map<String, DLNADevice> _dlnaDevices = {};

  /// 当前播放的设备
  DLNADevice? _currentDevice;

  /// 设备发现控制器
  final _deviceController = StreamController<List<CastDevice>>.broadcast();

  /// 设备流订阅
  StreamSubscription<Map<String, DLNADevice>>? _deviceSubscription;

  /// 设备发现流
  Stream<List<CastDevice>> get deviceStream => _deviceController.stream;

  /// 是否正在投屏
  bool get isCasting => _currentDevice != null;

  /// 开始设备发现
  Future<void> startDiscovery({Duration timeout = const Duration(seconds: 15)}) async {
    if (_isSearching) {
      logger.i('DLNA 设备搜索已在进行中');
      return;
    }

    _isSearching = true;
    _dlnaDevices.clear();

    try {
      _manager = DLNAManager();

      logger.i('开始搜索 DLNA 设备...');

      // 启动设备管理器
      _deviceManager = await _manager!.start();

      // 监听设备发现
      // 注意：dlna_dart 库的 DeviceManager 会累积设备，这里合并更新而非清空
      _deviceSubscription = _deviceManager!.devices.stream.listen((deviceMap) {
        for (final entry in deviceMap.entries) {
          final device = entry.value;
          // 只关注渲染器（可以接收视频的设备）
          if (device.info.deviceType.contains('MediaRenderer')) {
            final isNew = !_dlnaDevices.containsKey(device.info.URLBase);
            if (isNew) {
              logger.i('发现新 DLNA 设备: ${device.info.friendlyName} @ ${device.info.URLBase}');
            }
            // 使用 URLBase 作为 key，与 CastDevice.id 保持一致
            _dlnaDevices[device.info.URLBase] = device;
          }
        }

        logger.d('DLNA 设备总数: ${_dlnaDevices.length}');
        // 发送更新
        _deviceController.add(_convertToCastDevices());
      });

      // 设置超时
      Timer(timeout, () {
        if (_isSearching) {
          logger.i('DLNA 设备搜索超时，共发现 ${_dlnaDevices.length} 个设备');
          stopDiscovery();
        }
      });
    } catch (e, st) {
      AppError.handle(e, st, 'dlnaStartDiscovery');
      _isSearching = false;
    }
  }

  /// 停止设备发现
  void stopDiscovery() {
    _isSearching = false;
    _deviceSubscription?.cancel();
    _deviceSubscription = null;
    _manager?.stop();
    _manager = null;
    _deviceManager = null;
    logger.i('停止 DLNA 设备搜索');
  }

  /// 获取当前发现的设备列表
  List<CastDevice> getDiscoveredDevices() => _convertToCastDevices();

  /// 转换为 CastDevice 列表
  List<CastDevice> _convertToCastDevices() => _dlnaDevices.values.map((device) {
        final info = device.info;
        return CastDevice(
          id: info.URLBase,
          name: info.friendlyName,
          protocol: CastProtocol.dlna,
          address: _extractAddress(info.URLBase),
          port: _extractPort(info.URLBase),
        );
      }).toList();

  /// 从 URL 提取地址
  String _extractAddress(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (e) {
      return '';
    }
  }

  /// 从 URL 提取端口
  int _extractPort(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.port;
    } catch (e) {
      return 0;
    }
  }

  /// 投屏视频
  ///
  /// 当 [subtitleUrl] 不为 null 时，会构造带字幕扩展的 DIDL-Lite metadata
  /// 直接调用 `SetAVTransportURI`，覆盖 dlna_dart 内置不带字幕的实现。
  /// 兼容三种主流字幕扩展（最大化设备兼容性）：
  /// - 三星 sec:CaptionInfoEx
  /// - 通用 res protocolInfo=text/srt
  /// - Sony pv:subtitleFileUri / subtitleFileType
  /// 如果带字幕的请求失败，会自动回退到不带字幕的常规投屏。
  Future<bool> castVideo({
    required String deviceId,
    required String videoUrl,
    required String title,
    String? subtitleUrl,
    String? subtitleMime,
  }) async {
    // 找到对应的 DLNA 设备
    final device = _dlnaDevices[deviceId];
    if (device == null) {
      // 尝试通过遍历查找（兼容旧版本数据）
      final foundDevice = _dlnaDevices.values.firstWhere(
        (d) => d.info.URLBase == deviceId || d.info.friendlyName == deviceId,
        orElse: () => throw Exception(appL10n.dlnaDeviceNotFound(deviceId)),
      );
      _currentDevice = foundDevice;
    } else {
      _currentDevice = device;
    }

    try {
      logger
        ..i('开始投屏到 ${_currentDevice!.info.friendlyName}')
        ..i('视频URL: $videoUrl');

      var subtitleApplied = false;
      if (subtitleUrl != null && subtitleUrl.isNotEmpty) {
        try {
          await _setAvTransportUriWithSubtitle(
            device: _currentDevice!,
            videoUrl: videoUrl,
            title: title,
            subtitleUrl: subtitleUrl,
            subtitleMime: subtitleMime ?? _guessSubtitleMime(subtitleUrl),
          );
          subtitleApplied = true;
          logger.i('DLNA: 已附带字幕 metadata 投屏 $subtitleUrl');
        } on Exception catch (e, st) {
          AppError.ignore(e, st, '带字幕投屏失败，回退到不带字幕');
        }
      }

      if (!subtitleApplied) {
        // 标准投屏（不带字幕，或带字幕请求失败时回退）
        await _currentDevice!.setUrl(videoUrl, title: title, type: PlayType.Video);
      }

      // 播放
      await _currentDevice!.play();

      logger.i('投屏成功');
      return true;
    } catch (e, st) {
      AppError.handle(e, st, 'dlnaCastVideo', {'deviceId': deviceId, 'videoUrl': videoUrl});
      _currentDevice = null;
      return false;
    }
  }

  /// 调用 DLNA 设备的 `SetAVTransportURI`，附带字幕的 DIDL-Lite metadata
  ///
  /// 直接调用 dlna_dart 暴露的 [DLNADevice.request] 提交手工构造的 SOAP envelope。
  Future<void> _setAvTransportUriWithSubtitle({
    required DLNADevice device,
    required String videoUrl,
    required String title,
    required String subtitleUrl,
    required String subtitleMime,
  }) async {
    final encodedVideoUrl = _xmlEscape(videoUrl);
    final encodedSubtitleUrl = _xmlEscape(subtitleUrl);
    final encodedTitle = _xmlEscape(title);
    final subtitleType = subtitleMime.endsWith('vtt')
        ? 'vtt'
        : subtitleMime.endsWith('ass')
            ? 'ass'
            : 'srt';

    // DIDL-Lite metadata：三种字幕扩展同时携带，提高设备兼容性
    final metadata = '''<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:sec="http://www.sec.co.kr/" xmlns:pv="http://www.pv.com/pvns/"><item id="false" parentID="1" restricted="0"><dc:title>$encodedTitle</dc:title><dc:creator>unknown</dc:creator><upnp:class>object.item.videoItem</upnp:class><res protocolInfo="http-get:*:video/mp4:*" pv:subtitleFileUri="$encodedSubtitleUrl" pv:subtitleFileType="$subtitleType">$encodedVideoUrl</res><res protocolInfo="http-get:*:text/$subtitleType:*">$encodedSubtitleUrl</res><sec:CaptionInfoEx sec:type="$subtitleType">$encodedSubtitleUrl</sec:CaptionInfoEx><sec:CaptionInfo sec:type="$subtitleType">$encodedSubtitleUrl</sec:CaptionInfo></item></DIDL-Lite>''';

    final escapedMetadata = _xmlEscape(metadata);

    // XML 声明必须位于内容起始处，前面不能有换行/空白，故保留首行不换行。
    // ignore: leading_newlines_in_multiline_strings
    final envelope = '''<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
    <s:Body>
        <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
            <InstanceID>0</InstanceID>
            <CurrentURI>$encodedVideoUrl</CurrentURI>
            <CurrentURIMetaData>$escapedMetadata</CurrentURIMetaData>
        </u:SetAVTransportURI>
    </s:Body>
</s:Envelope>''';

    await device.request('SetAVTransportURI', utf8.encode(envelope));
  }

  String _guessSubtitleMime(String url) {
    final lower = url.toLowerCase();
    if (lower.endsWith('.vtt')) return 'text/vtt';
    if (lower.endsWith('.ass') || lower.endsWith('.ssa')) return 'text/x-ssa';
    return 'text/srt';
  }

  String _xmlEscape(String input) => input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// 播放
  Future<void> play() async {
    if (_currentDevice == null) return;

    try {
      await _currentDevice!.play();
    } catch (e, st) {
      AppError.handle(e, st, 'dlnaPlay');
    }
  }

  /// 暂停
  Future<void> pause() async {
    if (_currentDevice == null) return;

    try {
      await _currentDevice!.pause();
    } catch (e, st) {
      AppError.handle(e, st, 'dlnaPause');
    }
  }

  /// 停止
  Future<void> stop() async {
    if (_currentDevice == null) return;

    try {
      await _currentDevice!.stop();
      _currentDevice = null;
    } catch (e, st) {
      AppError.handle(e, st, 'dlnaStop');
    }
  }

  /// 跳转到指定位置
  Future<void> seek(Duration position) async {
    if (_currentDevice == null) return;

    try {
      // 转换为 HH:MM:SS 格式
      final timeStr = _formatDurationToString(position);
      await _currentDevice!.seek(timeStr);
    } catch (e, st) {
      AppError.handle(e, st, 'dlnaSeek');
    }
  }

  /// 设置音量
  Future<void> setVolume(int volume) async {
    if (_currentDevice == null) return;

    try {
      await _currentDevice!.volume(volume.clamp(0, 100));
    } catch (e, st) {
      AppError.handle(e, st, 'dlnaSetVolume');
    }
  }

  /// 获取当前播放位置
  Future<Duration?> getPosition() async {
    if (_currentDevice == null) return null;

    try {
      final positionXml = await _currentDevice!.position();
      final parser = PositionParser(positionXml);
      return Duration(seconds: parser.RelTimeInt);
    } catch (e, st) {
      AppError.ignore(e, st, '获取播放位置失败（正常情况下可能未开始播放）');
      return null;
    }
  }

  /// 获取播放时长
  Future<Duration?> getDuration() async {
    if (_currentDevice == null) return null;

    try {
      final positionXml = await _currentDevice!.position();
      final parser = PositionParser(positionXml);
      return Duration(seconds: parser.TrackDurationInt);
    } catch (e, st) {
      AppError.ignore(e, st, '获取播放时长失败');
      return null;
    }
  }

  /// 获取播放状态
  Future<CastPlaybackState> getPlaybackState() async {
    if (_currentDevice == null) return CastPlaybackState.idle;

    try {
      final transportXml = await _currentDevice!.getTransportInfo();
      final parser = TransportInfoParser(transportXml);
      return _convertTransportState(parser.CurrentTransportState);
    } catch (e, st) {
      AppError.ignore(e, st, '获取播放状态失败');
      return CastPlaybackState.idle;
    }
  }

  /// 转换传输状态
  CastPlaybackState _convertTransportState(String state) => switch (state.toUpperCase()) {
        'PLAYING' => CastPlaybackState.playing,
        'PAUSED_PLAYBACK' || 'PAUSED' => CastPlaybackState.paused,
        'STOPPED' => CastPlaybackState.stopped,
        'TRANSITIONING' => CastPlaybackState.loading,
        'NO_MEDIA_PRESENT' => CastPlaybackState.idle,
        _ => CastPlaybackState.idle,
      };

  /// 将 Duration 转换为 HH:MM:SS 格式字符串
  String _formatDurationToString(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 释放资源
  void dispose() {
    stopDiscovery();
    _deviceController.close();
    _currentDevice = null;
    _dlnaDevices.clear();
  }
}
