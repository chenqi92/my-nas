import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/domain/entities/video_quality.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Android MediaCodec 转码服务
///
/// 使用 Android 原生 MediaCodec API 进行硬件加速转码
/// 仅支持 Android 平台
class AndroidMediaCodecTranscoding {
  AndroidMediaCodecTranscoding._();

  static AndroidMediaCodecTranscoding? _instance;

  static AndroidMediaCodecTranscoding get instance {
    _instance ??= AndroidMediaCodecTranscoding._();
    return _instance!;
  }

  static const _methodChannel = MethodChannel('com.kkape.mynas/mediacodec_transcoding');
  static const _eventChannel = EventChannel('com.kkape.mynas/mediacodec_transcoding_progress');

  bool _isInitialized = false;
  bool _isAvailable = false;

  StreamSubscription<dynamic>? _progressSubscription;
  final Map<String, StreamController<TranscodeProgress>> _progressControllers = {};

  /// 是否可用
  bool get isAvailable => _isAvailable && Platform.isAndroid;

  /// 初始化服务
  Future<void> init() async {
    if (_isInitialized) return;

    if (!Platform.isAndroid) {
      logger.i('MediaCodecTranscoding: 非 Android 平台，跳过初始化');
      _isInitialized = true;
      return;
    }

    try {
      final result = await _methodChannel.invokeMethod<bool>('isAvailable');
      _isAvailable = result ?? false;

      if (_isAvailable) {
        // 监听进度事件
        _progressSubscription = _eventChannel.receiveBroadcastStream().listen(
          _handleProgressEvent,
          onError: (Object error) {
            logger.e('MediaCodecTranscoding: 进度事件错误: $error');
          },
        );

        logger.i('MediaCodecTranscoding: 初始化成功');
      } else {
        logger.w('MediaCodecTranscoding: 不可用');
      }
    } catch (e, st) {
      AppError.ignore(e, st, 'MediaCodecTranscoding 初始化失败');
      _isAvailable = false;
    }

    _isInitialized = true;
  }

  /// 处理进度事件
  void _handleProgressEvent(dynamic event) {
    if (event is! Map) return;

    final taskId = event['taskId'] as String?;
    final type = event['type'] as String?;

    if (taskId == null || type == null) return;

    final controller = _progressControllers[taskId];
    if (controller == null) return;

    switch (type) {
      case 'progress':
        final progress = (event['progress'] as num?)?.toDouble() ?? 0.0;
        final speed = event['speed'] as String?;
        controller.add(TranscodeProgress(
          status: TranscodeStatus.transcoding,
          progress: progress,
          speed: speed,
        ));

      case 'complete':
        final outputPath = event['outputPath'] as String?;
        controller.add(TranscodeProgress(
          status: TranscodeStatus.completed,
          progress: 1.0,
          outputPath: outputPath,
        ));
        controller.close();
        _progressControllers.remove(taskId);

      case 'error':
        final message = event['message'] as String?;
        controller.add(TranscodeProgress(
          status: TranscodeStatus.error,
          error: message,
        ));
        controller.close();
        _progressControllers.remove(taskId);

      case 'cancelled':
        controller.add(const TranscodeProgress(
          status: TranscodeStatus.cancelled,
        ));
        controller.close();
        _progressControllers.remove(taskId);
    }
  }

  /// 开始转码
  ///
  /// 返回 (taskId, progressStream, resultFuture)
  Future<TranscodeSession?> startTranscode({
    required String inputPath,
    required VideoQuality quality,
    Duration? startPosition,
  }) async {
    if (!isAvailable) {
      logger.w('MediaCodecTranscoding: 服务不可用');
      return null;
    }

    if (quality.isOriginal) {
      logger.d('MediaCodecTranscoding: 原画质量，无需转码');
      return null;
    }

    try {
      final taskId = const Uuid().v4();
      final tempDir = await getTemporaryDirectory();
      final outputPath = '${tempDir.path}/mediacodec_$taskId.mp4';

      // 创建进度控制器
      final progressController = StreamController<TranscodeProgress>.broadcast();
      _progressControllers[taskId] = progressController;

      // 调用原生方法
      final resultFuture = _methodChannel.invokeMethod<Map<Object?, Object?>>(
        'startTranscode',
        {
          'taskId': taskId,
          'inputPath': inputPath,
          'outputPath': outputPath,
          'targetWidth': quality.maxWidth,
          'targetHeight': quality.maxHeight,
          'targetBitrate': quality.estimatedBitrate,
          'audioBitrate': 128000,
          'startPositionMs': startPosition?.inMilliseconds ?? 0,
        },
      );

      logger.i('MediaCodecTranscoding: 开始转码任务 $taskId');
      logger.d('MediaCodecTranscoding: $inputPath -> $outputPath');
      logger.d('MediaCodecTranscoding: 目标分辨率 ${quality.maxWidth}x${quality.maxHeight}');

      return TranscodeSession(
        taskId: taskId,
        outputPath: outputPath,
        progressStream: progressController.stream,
        resultFuture: resultFuture.then((result) {
          final success = result?['success'] as bool? ?? false;
          final error = result?['error'] as String?;
          final path = result?['outputPath'] as String?;

          if (success && path != null) {
            return TranscodeResult.success(path);
          } else {
            return TranscodeResult.error(error ?? 'Unknown error');
          }
        }),
      );
    } catch (e, st) {
      AppError.handle(e, st, 'mediacodecStartTranscode');
      return null;
    }
  }

  /// 取消转码
  Future<void> cancelTranscode(String taskId) async {
    try {
      await _methodChannel.invokeMethod<bool>('cancelTranscode', {
        'taskId': taskId,
      });
      logger.i('MediaCodecTranscoding: 已请求取消任务 $taskId');
    } catch (e, st) {
      AppError.ignore(e, st, 'MediaCodecTranscoding 取消失败');
    }
  }

  /// 获取支持的编码器列表
  Future<List<String>> getSupportedEncoders() async {
    if (!Platform.isAndroid) return [];

    try {
      final result = await _methodChannel.invokeMethod<List<Object?>>('getSupportedEncoders');
      return result?.map((e) => e.toString()).toList() ?? [];
    } catch (e, st) {
      AppError.ignore(e, st, '获取支持的编码器列表失败');
      return [];
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    await _progressSubscription?.cancel();
    _progressSubscription = null;

    for (final controller in _progressControllers.values) {
      await controller.close();
    }
    _progressControllers.clear();
  }
}

/// 转码会话
class TranscodeSession {
  TranscodeSession({
    required this.taskId,
    required this.outputPath,
    required this.progressStream,
    required this.resultFuture,
  });

  final String taskId;
  final String outputPath;
  final Stream<TranscodeProgress> progressStream;
  final Future<TranscodeResult> resultFuture;
}

/// 转码进度
class TranscodeProgress {
  const TranscodeProgress({
    required this.status,
    this.progress = 0.0,
    this.speed,
    this.outputPath,
    this.error,
  });

  final TranscodeStatus status;
  final double progress;
  final String? speed;
  final String? outputPath;
  final String? error;
}

/// 转码状态
enum TranscodeStatus {
  idle,
  transcoding,
  completed,
  error,
  cancelled,
}

/// 转码结果
sealed class TranscodeResult {
  const TranscodeResult();

  factory TranscodeResult.success(String outputPath) = TranscodeResultSuccess;
  factory TranscodeResult.error(String message) = TranscodeResultError;
}

class TranscodeResultSuccess extends TranscodeResult {
  const TranscodeResultSuccess(this.outputPath);
  final String outputPath;
}

class TranscodeResultError extends TranscodeResult {
  const TranscodeResultError(this.message);
  final String message;
}
