import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/transcoding/nas_transcoding_service.dart';
import 'package:my_nas/features/video/data/services/transcoding/transcoding_capability.dart';
import 'package:my_nas/features/video/domain/entities/video_quality.dart';
import 'package:uuid/uuid.dart';

/// Jellyfin 转码服务
///
/// 使用 Jellyfin 服务器的转码 API 进行视频转码
/// 参考文档: https://api.jellyfin.org/
class JellyfinTranscodingService implements NasTranscodingService {
  JellyfinTranscodingService({
    required String serverUrl,
    required String apiKey,
    required String userId,
    Dio? dio,
  })  : _serverUrl = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl,
        _apiKey = apiKey,
        _userId = userId,
        _dio = dio ?? Dio();

  final String _serverUrl;
  final String _apiKey;
  final String _userId;
  final Dio _dio;

  /// 活跃的转码会话
  final Map<String, _JellyfinSession> _sessions = {};

  @override
  bool get isAvailable => _apiKey.isNotEmpty && _userId.isNotEmpty;

  @override
  TranscodingCapability get capability => TranscodingCapability.serverSide;

  @override
  Future<String?> getTranscodedStreamUrl({
    required String videoPath,
    required VideoQuality quality,
    Duration? startPosition,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    try {
      // 从路径中提取 itemId (Jellyfin 使用 itemId 而不是路径)
      final itemId = _extractItemId(videoPath);
      if (itemId == null) {
        logger.w('JellyfinTranscoding: 无法从路径提取 itemId: $videoPath');
        return null;
      }

      // 如果是原画质量，使用直接播放
      if (quality.isOriginal) {
        return _getDirectStreamUrl(itemId);
      }

      // 构建转码流 URL
      final params = _buildTranscodeParams(
        itemId: itemId,
        quality: quality,
        startPosition: startPosition,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
      );

      final url = '$_serverUrl/Videos/$itemId/stream?$params';
      logger
        ..i('JellyfinTranscoding: 转码流 URL 已生成')
        ..d('JellyfinTranscoding: URL => $url');

      return url;
    } catch (e, st) {
      AppError.handle(e, st, 'jellyfinGetTranscodedStreamUrl');
      return null;
    }
  }

  @override
  Future<List<VideoQuality>> getAvailableQualities({
    required String videoPath,
    int? originalWidth,
    int? originalHeight,
  }) async {
    // Jellyfin 支持动态转码，基于原始分辨率返回可用清晰度
    if (originalWidth != null && originalHeight != null) {
      return VideoQuality.getAvailableQualities(
        videoWidth: originalWidth,
        videoHeight: originalHeight,
      );
    }

    // 如果没有分辨率信息，返回所有可能的清晰度
    return VideoQuality.values.toList();
  }

  @override
  Future<TranscodingSession?> startSession({
    required String videoPath,
    required VideoQuality quality,
  }) async {
    try {
      final itemId = _extractItemId(videoPath);
      if (itemId == null) return null;

      // 生成会话 ID
      final sessionId = const Uuid().v4();

      // 获取转码流 URL
      final streamUrl = await getTranscodedStreamUrl(
        videoPath: videoPath,
        quality: quality,
      );

      if (streamUrl == null) return null;

      // 报告播放开始
      await _reportPlaybackStart(itemId);

      // 创建会话
      final session = _JellyfinSession(
        sessionId: sessionId,
        itemId: itemId,
        streamUrl: streamUrl,
        quality: quality,
        startTime: DateTime.now(),
      );

      _sessions[sessionId] = session;

      logger.i('JellyfinTranscoding: 会话已创建 $sessionId');

      return TranscodingSession(
        sessionId: sessionId,
        streamUrl: streamUrl,
        quality: quality,
      );
    } catch (e, st) {
      AppError.handle(e, st, 'jellyfinStartSession');
      return null;
    }
  }

  @override
  Future<void> stopSession(String sessionId) async {
    final session = _sessions.remove(sessionId);
    if (session == null) return;

    try {
      // 报告播放停止
      await _reportPlaybackStop(session.itemId);
      logger.i('JellyfinTranscoding: 会话已停止 $sessionId');
    } catch (e, st) {
      AppError.ignore(e, st, 'stopSession 报告失败');
    }
  }

  @override
  Future<TranscodingProgress?> getProgress(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) return null;

    // Jellyfin 不提供转码进度，返回转码中状态
    return const TranscodingProgress(
      status: TranscodingStatus.transcoding,
      progress: -1, // 不确定进度
    );
  }

  @override
  Future<void> dispose() async {
    // 停止所有会话
    for (final sessionId in _sessions.keys.toList()) {
      await stopSession(sessionId);
    }
    _sessions.clear();
  }

  /// 从路径中提取 Jellyfin itemId
  ///
  /// Jellyfin 的视频路径格式通常是:
  /// - jellyfin://itemId
  /// - /jellyfin/items/itemId
  /// - 直接是 itemId
  String? _extractItemId(String path) {
    // 尝试匹配 jellyfin:// 格式
    if (path.startsWith('jellyfin://')) {
      return path.substring('jellyfin://'.length);
    }

    // 尝试匹配 /jellyfin/items/ 格式
    final itemsMatch = RegExp('/jellyfin/items/([^/]+)').firstMatch(path);
    if (itemsMatch != null) {
      return itemsMatch.group(1);
    }

    // 尝试匹配 GUID 格式 (Jellyfin itemId 是 GUID)
    final guidMatch = RegExp(
      r'^[0-9a-f]{32}$|^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).firstMatch(path);
    if (guidMatch != null) {
      return path;
    }

    return null;
  }

  /// 获取直接播放 URL
  String _getDirectStreamUrl(String itemId) =>
      '$_serverUrl/Videos/$itemId/stream?Static=true&api_key=$_apiKey';

  /// 构建转码参数
  String _buildTranscodeParams({
    required String itemId,
    required VideoQuality quality,
    Duration? startPosition,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) {
    final params = <String, String>{
      'api_key': _apiKey,
      'UserId': _userId,
      'Static': 'false',
      'Container': 'ts', // HLS 容器
      'AudioCodec': 'aac',
      'VideoCodec': 'h264',
      'TranscodingProtocol': 'hls',
    };

    // 设置分辨率限制
    if (!quality.isOriginal) {
      if (quality.maxWidth != null) {
        params['MaxWidth'] = quality.maxWidth.toString();
      }
      if (quality.maxHeight != null) {
        params['MaxHeight'] = quality.maxHeight.toString();
      }
      if (quality.estimatedBitrate != null) {
        params['VideoBitRate'] = quality.estimatedBitrate.toString();
      }
    }

    // 设置起始位置
    if (startPosition != null && startPosition > Duration.zero) {
      // Jellyfin 使用 ticks (1 tick = 100 nanoseconds)
      final ticks = startPosition.inMicroseconds * 10;
      params['StartTimeTicks'] = ticks.toString();
    }

    // 设置音轨
    if (audioStreamIndex != null) {
      params['AudioStreamIndex'] = audioStreamIndex.toString();
    }

    // 设置字幕
    if (subtitleStreamIndex != null && subtitleStreamIndex >= 0) {
      params['SubtitleStreamIndex'] = subtitleStreamIndex.toString();
      params['SubtitleMethod'] = 'Encode'; // 烧录字幕
    }

    return params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }

  /// 报告播放开始
  Future<void> _reportPlaybackStart(String itemId) async {
    try {
      await _dio.post<void>(
        '$_serverUrl/Sessions/Playing',
        data: jsonEncode({
          'ItemId': itemId,
          'CanSeek': true,
          'PlayMethod': 'Transcode',
        }),
        options: Options(
          headers: {
            'X-Emby-Token': _apiKey,
            'Content-Type': 'application/json',
          },
        ),
      );
    } catch (e, st) {
      AppError.ignore(e, st, 'reportPlaybackStart 失败');
    }
  }

  /// 报告播放停止
  Future<void> _reportPlaybackStop(String itemId) async {
    try {
      await _dio.post<void>(
        '$_serverUrl/Sessions/Playing/Stopped',
        data: jsonEncode({
          'ItemId': itemId,
        }),
        options: Options(
          headers: {
            'X-Emby-Token': _apiKey,
            'Content-Type': 'application/json',
          },
        ),
      );
    } catch (e, st) {
      AppError.ignore(e, st, 'reportPlaybackStop 失败');
    }
  }
}

/// Jellyfin 会话内部类
class _JellyfinSession {
  _JellyfinSession({
    required this.sessionId,
    required this.itemId,
    required this.streamUrl,
    required this.quality,
    required this.startTime,
  });

  final String sessionId;
  final String itemId;
  final String streamUrl;
  final VideoQuality quality;
  final DateTime startTime;
}
