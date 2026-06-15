import 'dart:async';

import 'package:dio/dio.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/transcoding/nas_transcoding_service.dart';
import 'package:my_nas/features/video/data/services/transcoding/transcoding_capability.dart';
import 'package:my_nas/features/video/domain/entities/video_quality.dart';
import 'package:uuid/uuid.dart';

/// Synology Video Station 转码服务
///
/// 使用 Synology Video Station 的转码 API
/// 注意: Video Station 需要单独安装，且需要有效的 Video Station 许可证
///
/// API 端点:
/// - SYNO.VideoStation.Streaming: open, stream, close
/// - path: VideoStation/vtestreaming.cgi
class SynologyTranscodingService implements NasTranscodingService {
  SynologyTranscodingService({
    required String serverUrl,
    required String sessionId,
    Dio? dio,
  })  : _serverUrl = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl,
        _sid = sessionId,
        _dio = dio ?? Dio();

  final String _serverUrl;
  final String _sid;
  final Dio _dio;

  /// 是否已检测到 Video Station
  bool _videoStationAvailable = false;

  /// 活跃的转码会话
  final Map<String, _SynologySession> _sessions = {};

  @override
  bool get isAvailable => _sid.isNotEmpty && _videoStationAvailable;

  @override
  TranscodingCapability get capability =>
      _videoStationAvailable ? TranscodingCapability.serverSide : TranscodingCapability.none;

  /// 初始化服务，检测 Video Station 是否可用
  Future<void> init() async {
    try {
      // 查询 Video Station API 是否存在
      final response = await _dio.get<Map<String, dynamic>>(
        '$_serverUrl/webapi/entry.cgi',
        queryParameters: {
          'api': 'SYNO.API.Info',
          'version': 1,
          'method': 'query',
          'query': 'SYNO.VideoStation',
        },
      );

      final data = response.data;
      if (data?['success'] == true) {
        final apiData = data?['data'] as Map<String, dynamic>?;
        _videoStationAvailable = apiData?.containsKey('SYNO.VideoStation.Streaming') ?? false;
        logger.i('SynologyTranscoding: Video Station 检测结果 => $_videoStationAvailable');
      } else {
        _videoStationAvailable = false;
        logger.w('SynologyTranscoding: Video Station 未安装或不可用');
      }
    } catch (e, st) {
      AppError.ignore(e, st, 'Video Station 检测失败');
      _videoStationAvailable = false;
    }
  }

  @override
  Future<String?> getTranscodedStreamUrl({
    required String videoPath,
    required VideoQuality quality,
    Duration? startPosition,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    if (!_videoStationAvailable) {
      logger.w('SynologyTranscoding: Video Station 不可用');
      return null;
    }

    try {
      // 首先需要获取视频在 Video Station 中的 ID
      final videoId = await _getVideoIdFromPath(videoPath);
      if (videoId == null) {
        logger.w('SynologyTranscoding: 无法获取视频 ID: $videoPath');
        return null;
      }

      // 如果是原画，使用直接下载
      if (quality.isOriginal) {
        return _getDirectStreamUrl(videoId);
      }

      // 开启流式会话
      final streamId = await _openStreamingSession(videoId, quality);
      if (streamId == null) {
        logger.w('SynologyTranscoding: 无法开启流式会话');
        return null;
      }

      // 构建流 URL
      final url = _buildStreamUrl(streamId, quality, startPosition);
      logger.i('SynologyTranscoding: 转码流 URL 已生成');

      return url;
    } catch (e, st) {
      AppError.handle(e, st, 'synologyGetTranscodedStreamUrl');
      return null;
    }
  }

  @override
  Future<List<VideoQuality>> getAvailableQualities({
    required String videoPath,
    int? originalWidth,
    int? originalHeight,
  }) async {
    if (!_videoStationAvailable) {
      return [VideoQuality.original];
    }

    // Synology Video Station 支持的转码清晰度
    // 通常支持: 原画, 1080p, 720p, 480p, 360p
    final qualities = <VideoQuality>[VideoQuality.original];

    if (originalWidth != null && originalHeight != null) {
      // 根据原始分辨率过滤
      if (originalHeight >= 1080) {
        qualities.addAll([
          VideoQuality.quality1080p,
          VideoQuality.quality720p,
          VideoQuality.quality480p,
          VideoQuality.quality360p,
        ]);
      } else if (originalHeight >= 720) {
        qualities.addAll([
          VideoQuality.quality720p,
          VideoQuality.quality480p,
          VideoQuality.quality360p,
        ]);
      } else if (originalHeight >= 480) {
        qualities.addAll([
          VideoQuality.quality480p,
          VideoQuality.quality360p,
        ]);
      }
    } else {
      // 没有分辨率信息，返回常见选项
      qualities.addAll([
        VideoQuality.quality1080p,
        VideoQuality.quality720p,
        VideoQuality.quality480p,
      ]);
    }

    return qualities;
  }

  @override
  Future<TranscodingSession?> startSession({
    required String videoPath,
    required VideoQuality quality,
  }) async {
    if (!_videoStationAvailable) return null;

    try {
      final streamUrl = await getTranscodedStreamUrl(
        videoPath: videoPath,
        quality: quality,
      );

      if (streamUrl == null) return null;

      final sessionId = const Uuid().v4();
      final session = _SynologySession(
        sessionId: sessionId,
        videoPath: videoPath,
        streamUrl: streamUrl,
        quality: quality,
        startTime: DateTime.now(),
      );

      _sessions[sessionId] = session;
      logger.i('SynologyTranscoding: 会话已创建 $sessionId');

      return TranscodingSession(
        sessionId: sessionId,
        streamUrl: streamUrl,
        quality: quality,
      );
    } catch (e, st) {
      AppError.handle(e, st, 'synologyStartSession');
      return null;
    }
  }

  @override
  Future<void> stopSession(String sessionId) async {
    final session = _sessions.remove(sessionId);
    if (session == null) return;

    // 目前简化处理，不需要显式关闭流式会话
    // Video Station 的流式会话会在客户端断开连接后自动关闭
    logger.i('SynologyTranscoding: 会话已停止 $sessionId');
  }

  @override
  Future<TranscodingProgress?> getProgress(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) return null;

    // Synology 不提供详细的转码进度
    return const TranscodingProgress(
      status: TranscodingStatus.transcoding,
      progress: -1,
    );
  }

  @override
  Future<void> dispose() async {
    for (final sessionId in _sessions.keys.toList()) {
      await stopSession(sessionId);
    }
    _sessions.clear();
  }

  /// 从文件路径获取 Video Station 中的视频 ID
  Future<int?> _getVideoIdFromPath(String path) async {
    try {
      // 搜索视频
      final response = await _dio.get<Map<String, dynamic>>(
        '$_serverUrl/webapi/entry.cgi',
        queryParameters: {
          'api': 'SYNO.VideoStation.Movie',
          'version': 1,
          'method': 'search',
          'keyword': path.split('/').last.replaceAll(RegExp(r'\.[^.]+$'), ''),
          '_sid': _sid,
        },
      );

      final data = response.data;
      if (data?['success'] == true) {
        final dataMap = data?['data'] as Map<String, dynamic>?;
        final movies = (dataMap?['movies'] as List<dynamic>?) ?? [];
        for (final movie in movies) {
          final movieMap = movie as Map<String, dynamic>;
          final additional = movieMap['additional'] as Map<String, dynamic>?;
          final file = additional?['file'] as Map<String, dynamic>?;
          final filePath = file?['path'] as String?;
          if (filePath == path) {
            return movieMap['id'] as int?;
          }
        }
      }

      return null;
    } catch (e, st) {
      AppError.ignore(e, st, '获取视频 ID 失败');
      return null;
    }
  }

  /// 获取直接播放 URL (原画)
  String _getDirectStreamUrl(int videoId) {
    final params = {
      'api': 'SYNO.VideoStation.Streaming',
      'version': '1',
      'method': 'stream',
      'id': videoId.toString(),
      'format': 'raw',
      '_sid': _sid,
    };

    final queryString = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');

    return '$_serverUrl/webapi/VideoStation/vtestreaming.cgi?$queryString';
  }

  /// 开启流式会话
  Future<String?> _openStreamingSession(int videoId, VideoQuality quality) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$_serverUrl/webapi/VideoStation/vtestreaming.cgi',
        queryParameters: {
          'api': 'SYNO.VideoStation.Streaming',
          'version': 3,
          'method': 'open',
          'id': videoId,
          'format': _getTranscodeFormat(quality),
          '_sid': _sid,
        },
      );

      final data = response.data;
      if (data?['success'] == true) {
        final dataMap = data?['data'] as Map<String, dynamic>?;
        return dataMap?['stream_id'] as String?;
      }

      return null;
    } catch (e, st) {
      AppError.ignore(e, st, '开启 Synology 流式会话失败');
      return null;
    }
  }

  /// 构建流 URL
  String _buildStreamUrl(String streamId, VideoQuality quality, Duration? startPosition) {
    final params = <String, String>{
      'api': 'SYNO.VideoStation.Streaming',
      'version': '3',
      'method': 'stream',
      'stream_id': streamId,
      '_sid': _sid,
    };

    if (startPosition != null && startPosition > Duration.zero) {
      params['position'] = startPosition.inSeconds.toString();
    }

    final queryString = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');

    return '$_serverUrl/webapi/VideoStation/vtestreaming.cgi?$queryString';
  }

  /// 获取转码格式字符串
  // Synology Video Station 使用 format 参数指定转码质量
  // high, medium, low, mobile, raw
  String _getTranscodeFormat(VideoQuality quality) => switch (quality) {
        VideoQuality.original => 'raw',
        VideoQuality.quality4K => 'high',
        VideoQuality.quality1080p => 'high',
        VideoQuality.quality720p => 'medium',
        VideoQuality.quality480p => 'low',
        VideoQuality.quality360p => 'mobile',
      };
}

/// Synology 会话内部类
class _SynologySession {
  _SynologySession({
    required this.sessionId,
    required this.videoPath,
    required this.streamUrl,
    required this.quality,
    required this.startTime,
  });

  final String sessionId;
  final String videoPath;
  final String streamUrl;
  final VideoQuality quality;
  final DateTime startTime;
}
