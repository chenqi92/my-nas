import 'dart:async' show Completer, StreamController, Timer;
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/transcoding/android_mediacodec_transcoding.dart';
import 'package:my_nas/features/video/data/services/transcoding/nas_transcoding_service.dart';
import 'package:my_nas/features/video/data/services/transcoding/transcoding_capability.dart';
import 'package:my_nas/features/video/domain/entities/video_quality.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 客户端 FFmpeg 转码服务
///
/// 使用本地 FFmpeg 进行视频转码，适用于不支持服务端转码的源
/// 例如: SMB, FTP, WebDAV 等
///
/// 各平台 FFmpeg 支持:
/// - iOS/Android/macOS: 使用 ffmpeg_kit_flutter_new 依赖
/// - Windows: 优先使用应用目录中打包的 FFmpeg（windows/ffmpeg/），回退到系统 PATH
/// - Linux: 使用系统安装的 FFmpeg
class ClientTranscodingService implements NasTranscodingService {
  ClientTranscodingService();

  /// 是否支持转码
  bool _isAvailable = false;

  /// 临时文件目录
  Directory? _tempDir;

  /// 桌面端 FFmpeg 可执行文件路径
  String? _ffmpegPath;

  /// 检测到的硬件编码器（null 表示未检测，空字符串表示无硬件加速）
  String? _detectedHwEncoder;

  /// 是否已尝试过硬件编码（用于失败时回退）
  bool _hwEncoderFailed = false;

  /// 活跃的转码任务
  final Map<String, _TranscodingTask> _tasks = {};

  /// 转码进度控制器
  final Map<String, StreamController<TranscodingProgress>> _progressControllers = {};

  @override
  bool get isAvailable => _isAvailable;

  @override
  TranscodingCapability get capability =>
      _isAvailable ? TranscodingCapability.clientSide : TranscodingCapability.none;

  /// 初始化服务
  Future<void> init() async {
    try {
      // 获取临时目录
      _tempDir = await getTemporaryDirectory();

      // 检查 FFmpeg 是否可用
      _isAvailable = await _checkFfmpegAvailable();

      if (_isAvailable) {
        logger.i('ClientTranscoding: FFmpeg 可用，客户端转码已启用');
      } else {
        logger.w('ClientTranscoding: FFmpeg 不可用，客户端转码已禁用');
      }
    } catch (e, st) {
      AppError.ignore(e, st, '初始化客户端转码服务失败');
      _isAvailable = false;
    }
  }

  /// 检查 FFmpeg 是否可用
  Future<bool> _checkFfmpegAvailable() async {
    // Android 使用 MediaCodec 硬件转码
    if (Platform.isAndroid) {
      try {
        await AndroidMediaCodecTranscoding.instance.init();
        if (AndroidMediaCodecTranscoding.instance.isAvailable) {
          logger.i('ClientTranscoding: Android 使用 MediaCodec 硬件转码');
          return true;
        }
      } catch (e, st) {
        AppError.ignore(e, st, '初始化 MediaCodec 转码失败');
      }
      logger.w('ClientTranscoding: Android MediaCodec 不可用');
      return false;
    }

    // iOS 使用 ffmpeg_kit_flutter
    if (Platform.isIOS) {
      try {
        // 执行简单命令验证 FFmpeg 可用
        final session = await FFmpegKit.execute('-version');
        final returnCode = await session.getReturnCode();
        final isAvailable = ReturnCode.isSuccess(returnCode);
        if (isAvailable) {
          logger.i('ClientTranscoding: FFmpegKit 可用');
        } else {
          final logs = await session.getAllLogsAsString();
          logger.w('ClientTranscoding: FFmpegKit 不可用: $logs');
        }
        return isAvailable;
      } catch (e, st) {
        AppError.ignore(e, st, '检查 FFmpegKit 可用性失败');
        return false;
      }
    }

    // macOS 使用打包的 FFmpeg 二进制
    if (Platform.isMacOS) {
      _ffmpegPath = await _findMacOSBundledFfmpeg();
      if (_ffmpegPath != null) {
        logger.i('ClientTranscoding: macOS 找到打包的 FFmpeg: $_ffmpegPath');
        return true;
      }
      // 回退到系统 FFmpeg
      _ffmpegPath = await _findSystemFfmpeg();
      if (_ffmpegPath != null) {
        logger.i('ClientTranscoding: macOS 使用系统 FFmpeg: $_ffmpegPath');
        return true;
      }
      logger.w('ClientTranscoding: macOS 未找到可用的 FFmpeg');
      return false;
    }

    // Linux/Windows 使用系统/打包的 FFmpeg
    if (Platform.isLinux || Platform.isWindows) {
      _ffmpegPath = await _findDesktopFfmpeg();
      if (_ffmpegPath != null) {
        logger.i('ClientTranscoding: 找到 FFmpeg: $_ffmpegPath');
        return true;
      }
      return false;
    }
    return false;
  }

  /// 查找 macOS 打包的 FFmpeg 可执行文件
  ///
  /// macOS app bundle 结构:
  /// my_nas.app/Contents/MacOS/ffmpeg
  Future<String?> _findMacOSBundledFfmpeg() async {
    try {
      // 获取应用程序可执行文件所在目录
      final exePath = Platform.resolvedExecutable;
      final exeDir = File(exePath).parent.path;

      // macOS: 查找 MacOS/ffmpeg
      final bundledFfmpegPath = '$exeDir/ffmpeg';
      final ffmpegFile = File(bundledFfmpegPath);

      if (await ffmpegFile.exists()) {
        // 验证可执行
        final result = await Process.run(bundledFfmpegPath, ['-version']);
        if (result.exitCode == 0) {
          logger.d('ClientTranscoding: macOS 找到打包的 FFmpeg: $bundledFfmpegPath');
          return bundledFfmpegPath;
        }
      }
    } catch (e) {
      logger.d('ClientTranscoding: 查找 macOS 打包 FFmpeg 失败: $e');
    }
    return null;
  }

  /// 查找系统安装的 FFmpeg（通过 PATH）
  Future<String?> _findSystemFfmpeg() async {
    try {
      final result = await Process.run('ffmpeg', ['-version']);
      if (result.exitCode == 0) {
        logger.d('ClientTranscoding: 使用系统 PATH 中的 FFmpeg');
        return 'ffmpeg';
      }
    } catch (_) {
      // FFmpeg 不在 PATH 中
    }
    return null;
  }

  /// 查找桌面端 FFmpeg 可执行文件（仅用于 Linux/Windows）
  Future<String?> _findDesktopFfmpeg() async {
    // 1. 优先查找应用目录中打包的 FFmpeg
    final bundledPath = await _findBundledFfmpeg();
    if (bundledPath != null) {
      logger.d('ClientTranscoding: 使用打包的 FFmpeg: $bundledPath');
      return bundledPath;
    }

    // 2. 回退到系统 PATH 中的 FFmpeg
    return _findSystemFfmpeg();
  }

  /// 查找应用目录中打包的 FFmpeg
  Future<String?> _findBundledFfmpeg() async {
    try {
      // 获取应用程序可执行文件所在目录
      final exePath = Platform.resolvedExecutable;
      final exeDir = File(exePath).parent.path;

      // Windows: 查找 ffmpeg/ffmpeg.exe
      // Linux: 查找 ffmpeg/ffmpeg
      final ffmpegExeName = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
      final bundledFfmpegPath = '$exeDir/ffmpeg/$ffmpegExeName';

      final ffmpegFile = File(bundledFfmpegPath);
      if (await ffmpegFile.exists()) {
        // 验证可执行
        final result = await Process.run(bundledFfmpegPath, ['-version']);
        if (result.exitCode == 0) {
          return bundledFfmpegPath;
        }
      }
    } catch (e) {
      logger.d('ClientTranscoding: 查找打包 FFmpeg 失败: $e');
    }
    return null;
  }

  @override
  Future<String?> getTranscodedStreamUrl({
    required String videoPath,
    required VideoQuality quality,
    Duration? startPosition,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    if (!_isAvailable) {
      logger.w('ClientTranscoding: 转码不可用');
      return null;
    }

    // 如果是原画，不需要转码
    if (quality.isOriginal) {
      return null;
    }

    try {
      // 创建转码任务
      final taskId = const Uuid().v4();
      final outputPath = '${_tempDir!.path}/transcoded_$taskId.mkv';

      // 开始后台转码
      final task = _TranscodingTask(
        taskId: taskId,
        inputPath: videoPath,
        outputPath: outputPath,
        quality: quality,
        startPosition: startPosition,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
      );

      _tasks[taskId] = task;

      // 同步执行转码并等待完成
      await _startTranscoding(task);

      // 检查转码结果
      if (task.isCompleted && task.error == null) {
        // 验证输出文件存在
        final outputFile = File(outputPath);
        if (await outputFile.exists()) {
          return 'file://$outputPath';
        } else {
          logger.e('ClientTranscoding: 输出文件不存在 $outputPath');
          return null;
        }
      } else {
        logger.e('ClientTranscoding: 转码失败 ${task.error}');
        return null;
      }
    } catch (e, st) {
      AppError.handle(e, st, 'clientGetTranscodedStreamUrl');
      return null;
    }
  }

  @override
  Future<List<VideoQuality>> getAvailableQualities({
    required String videoPath,
    int? originalWidth,
    int? originalHeight,
  }) async {
    if (!_isAvailable) {
      return [VideoQuality.original];
    }

    // 客户端转码支持所有低于原始分辨率的清晰度
    if (originalWidth != null && originalHeight != null) {
      return VideoQuality.getAvailableQualities(
        videoWidth: originalWidth,
        videoHeight: originalHeight,
      );
    }

    // 默认返回常见清晰度
    return [
      VideoQuality.original,
      VideoQuality.quality1080p,
      VideoQuality.quality720p,
      VideoQuality.quality480p,
    ];
  }

  @override
  Future<TranscodingSession?> startSession({
    required String videoPath,
    required VideoQuality quality,
  }) async {
    if (!_isAvailable) return null;

    try {
      final streamUrl = await getTranscodedStreamUrl(
        videoPath: videoPath,
        quality: quality,
      );

      if (streamUrl == null) return null;

      final sessionId = const Uuid().v4();

      // 创建进度控制器
      _progressControllers[sessionId] = StreamController<TranscodingProgress>.broadcast();

      logger.i('ClientTranscoding: 会话已创建 $sessionId');

      return TranscodingSession(
        sessionId: sessionId,
        streamUrl: streamUrl,
        quality: quality,
      );
    } catch (e, st) {
      AppError.handle(e, st, 'clientStartSession');
      return null;
    }
  }

  @override
  Future<void> stopSession(String sessionId) async {
    // 关闭进度控制器
    await _progressControllers[sessionId]?.close();
    _progressControllers.remove(sessionId);

    logger.i('ClientTranscoding: 会话已停止 $sessionId');
  }

  @override
  Future<TranscodingProgress?> getProgress(String sessionId) async {
    // 查找对应的任务
    for (final task in _tasks.values) {
      if (task.isRunning) {
        return TranscodingProgress(
          status: TranscodingStatus.transcoding,
          progress: task.progress,
          speed: task.speed,
          eta: task.eta,
        );
      }
    }

    return const TranscodingProgress(status: TranscodingStatus.idle);
  }

  /// 获取转码进度流
  Stream<TranscodingProgress>? getProgressStream(String sessionId) =>
      _progressControllers[sessionId]?.stream;

  @override
  Future<void> dispose() async {
    // 停止所有任务
    for (final task in _tasks.values) {
      task.cancel();
    }
    _tasks.clear();

    // 关闭所有控制器
    for (final controller in _progressControllers.values) {
      await controller.close();
    }
    _progressControllers.clear();

    // 清理临时文件
    await _cleanupTempFiles();

    // 释放 Android MediaCodec 资源
    if (Platform.isAndroid) {
      await AndroidMediaCodecTranscoding.instance.dispose();
    }
  }

  /// 启动转码任务
  ///
  /// [waitForComplete] 如果为 true，等待转码完成；否则等待输出文件有数据就返回
  Future<void> _startTranscoding(_TranscodingTask task, {bool waitForComplete = false}) async {
    task.isRunning = true;

    try {
      // 如果输入是 HTTP URL，先验证可访问性
      if (task.inputPath.startsWith('http://') || task.inputPath.startsWith('https://')) {
        final isAccessible = await _checkUrlAccessible(task.inputPath);
        if (!isAccessible) {
          task.isRunning = false;
          task.error = '无法访问输入 URL';
          return;
        }
      }

      logger.i('ClientTranscoding: 开始转码 ${task.inputPath}');

      if (Platform.isAndroid) {
        // Android 使用 MediaCodec 硬件转码
        await _runMediaCodecTranscoding(task);
      } else if (Platform.isIOS) {
        // iOS 使用 FFmpegKit
        final args = _buildFfmpegArgs(task);
        final command = args.join(' ');
        logger.d('ClientTranscoding: FFmpeg 命令 => $command');
        await _runFFmpegKitTranscoding(task, command);
      } else {
        // macOS/Linux/Windows 使用 Process 执行打包的 FFmpeg
        final args = _buildFfmpegArgs(task);
        final command = args.join(' ');
        logger.d('ClientTranscoding: FFmpeg 命令 => $command');
        await _runDesktopTranscoding(task, args, waitForComplete: waitForComplete);
      }
    } catch (e, st) {
      task.isRunning = false;
      task.error = e.toString();
      AppError.handle(e, st, 'clientStartTranscoding');
    }
  }

  /// 使用 MediaCodec 转码（Android）
  Future<void> _runMediaCodecTranscoding(_TranscodingTask task) async {
    final mediaCodec = AndroidMediaCodecTranscoding.instance;

    if (!mediaCodec.isAvailable) {
      task.isRunning = false;
      task.error = 'MediaCodec 不可用';
      return;
    }

    try {
      final session = await mediaCodec.startTranscode(
        inputPath: task.inputPath,
        quality: task.quality,
        startPosition: task.startPosition,
      );

      if (session == null) {
        task.isRunning = false;
        task.error = '无法启动 MediaCodec 转码';
        return;
      }

      // 监听进度
      session.progressStream.listen((progress) {
        task.progress = progress.progress;
        task.speed = progress.speed;

        if (progress.status == TranscodeStatus.transcoding) {
          // 每隔一段时间输出日志
          if ((progress.progress * 100).toInt() % 10 == 0) {
            logger.d('ClientTranscoding: MediaCodec 进度 ${(progress.progress * 100).toStringAsFixed(1)}%');
          }
        }
      });

      // 等待转码完成
      final result = await session.resultFuture;

      task.isRunning = false;

      switch (result) {
        case TranscodeResultSuccess(:final outputPath):
          // 更新输出路径（MediaCodec 可能使用不同的路径）
          task.isCompleted = true;
          // 复制到预期的输出路径
          final srcFile = File(outputPath);
          if (await srcFile.exists() && outputPath != task.outputPath) {
            await srcFile.copy(task.outputPath);
            await srcFile.delete();
          }
          logger.i('ClientTranscoding: MediaCodec 转码完成 ${task.outputPath}');

        case TranscodeResultError(:final message):
          task.error = message;
          logger.e('ClientTranscoding: MediaCodec 转码失败: $message');
      }
    } catch (e, st) {
      task.isRunning = false;
      task.error = e.toString();
      AppError.handle(e, st, 'mediacodecTranscoding');
    }
  }

  /// 检查 URL 是否可访问
  Future<bool> _checkUrlAccessible(String url) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);

      final request = await client.headUrl(Uri.parse(url));
      final response = await request.close();

      final statusCode = response.statusCode;
      final contentLength = response.contentLength;

      logger.d('ClientTranscoding: URL 检查 - 状态码=$statusCode, 内容长度=$contentLength');

      client.close();

      if (statusCode >= 200 && statusCode < 400) {
        return true;
      } else {
        logger.e('ClientTranscoding: URL 不可访问，状态码=$statusCode');
        return false;
      }
    } catch (e) {
      logger.e('ClientTranscoding: URL 检查失败: $e');
      return false;
    }
  }

  /// 使用 FFmpegKit 转码（iOS/Android/macOS）
  ///
  /// 采用流式转码：等待输出文件有足够数据就返回，转码在后台继续
  Future<void> _runFFmpegKitTranscoding(_TranscodingTask task, String command) async {
    final readyCompleter = Completer<void>();
    var lastLogTime = DateTime.now();
    var hasError = false;
    const readTimeout = Duration(seconds: 60); // 60秒无输出则超时

    try {
      // 使用 executeAsync 以便添加回调
      final session = await FFmpegKit.executeAsync(
        command,
        // 完成回调
        (FFmpegSession session) async {
          task.ffmpegSession = session;
          final returnCode = await session.getReturnCode();

          if (ReturnCode.isSuccess(returnCode)) {
            task.isRunning = false;
            task.isCompleted = true;
            logger.i('ClientTranscoding: 后台转码完成 ${task.outputPath}');
          } else if (ReturnCode.isCancel(returnCode)) {
            task.isRunning = false;
            if (!hasError) {
              task.error = '转码已取消';
            }
            logger.i('ClientTranscoding: 转码已取消');
          } else {
            task.isRunning = false;
            final logs = await session.getAllLogsAsString();
            final errorSnippet = logs != null && logs.length > 500
                ? logs.substring(logs.length - 500)
                : logs ?? '';
            hasError = true;
            task.error = '转码失败';
            logger.e('ClientTranscoding: 转码失败 returnCode=$returnCode');
            logger.e('ClientTranscoding: FFmpeg 输出:\n$errorSnippet');

            // 检测是否是编码器相关错误，标记硬件编码失败以便回退
            if (_isEncoderError(logs ?? '')) {
              _markHwEncoderFailed();
            }
          }

          // 如果还没返回就完成了（可能是错误），通知等待方
          if (!readyCompleter.isCompleted) {
            readyCompleter.complete();
          }
        },
        // 日志回调
        (log) {
          lastLogTime = DateTime.now();
          final message = log.getMessage();
          // 只记录关键日志，避免刷屏
          if (message.contains('Error') ||
              message.contains('error') ||
              message.contains('Invalid') ||
              message.contains('failed') ||
              message.contains('Input #') ||
              message.contains('Output #') ||
              message.contains('Stream #')) {
            logger.d('ClientTranscoding: FFmpeg: $message');
          }
        },
        // 统计回调
        (Statistics statistics) {
          lastLogTime = DateTime.now();
          final timeInMs = statistics.getTime().toDouble();
          if (timeInMs > 0) {
            task.currentTime = Duration(milliseconds: timeInMs.round());
            // 如果知道总时长，计算进度
            if (task.totalDuration != null && task.totalDuration! > Duration.zero) {
              task.progress = timeInMs / task.totalDuration!.inMilliseconds;
            }
            // 每10秒输出一次进度日志
            if (timeInMs.round() % 10000 < 500) {
              logger.d('ClientTranscoding: 进度 ${(timeInMs / 1000).toStringAsFixed(1)}s, 速度=${statistics.getSpeed().toStringAsFixed(1)}x');
            }
          }
          task.speed = '${(statistics.getSpeed()).toStringAsFixed(1)}x';
        },
      );

      task.ffmpegSession = session;

      // 流式转码：等待输出文件有足够数据就返回
      final outputFile = File(task.outputPath);
      const minFileSize = 2 * 1024 * 1024; // 至少 2MB 缓冲
      const maxWaitTime = Duration(seconds: 60); // 最多等待 60 秒
      const checkInterval = Duration(milliseconds: 500);

      final startTime = DateTime.now();
      var fileReady = false;
      Timer? timeoutTimer;

      // 启动超时监控
      timeoutTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
        if (readyCompleter.isCompleted || !task.isRunning) {
          timer.cancel();
          return;
        }

        final timeSinceLastLog = DateTime.now().difference(lastLogTime);
        if (timeSinceLastLog > readTimeout) {
          logger.e('ClientTranscoding: FFmpeg 超时，${readTimeout.inSeconds}秒无输出');
          hasError = true;
          task.cancel();
          task.error = '转码超时：输入源无响应';
          timer.cancel();
          if (!readyCompleter.isCompleted) {
            readyCompleter.complete();
          }
        }
      });

      // 等待输出文件有足够数据
      while (DateTime.now().difference(startTime) < maxWaitTime) {
        // 检查是否已出错或取消
        if (readyCompleter.isCompleted) {
          break;
        }

        await Future<void>.delayed(checkInterval);

        // 检查输出文件大小
        if (await outputFile.exists()) {
          final size = await outputFile.length();
          if (size >= minFileSize) {
            logger.i('ClientTranscoding: 流式输出就绪，文件大小: ${size ~/ 1024}KB');
            fileReady = true;
            break;
          }
        }
      }

      timeoutTimer.cancel();

      if (fileReady) {
        // 文件已有足够数据，可以开始播放
        // 注意：转码仍在后台继续
        task.isCompleted = true; // 标记为"可播放"状态
        logger.i('ClientTranscoding: 流式转码已就绪 ${task.outputPath}');
      } else if (!readyCompleter.isCompleted) {
        // 等待超时且没有错误
        hasError = true;
        task.isRunning = false;
        task.error = '等待转码输出超时';
        task.cancel();
        logger.e('ClientTranscoding: 等待转码输出超时');
      }

      // 完成等待
      if (!readyCompleter.isCompleted) {
        readyCompleter.complete();
      }
    } catch (e, st) {
      task.isRunning = false;
      task.error = e.toString();
      AppError.handle(e, st, 'mobileTranscoding');
      if (!readyCompleter.isCompleted) {
        readyCompleter.complete();
      }
    }
  }

  /// 桌面端转码（使用 Process）
  ///
  /// [waitForComplete] 如果为 true，等待转码完成；否则等待输出文件有数据就返回
  Future<void> _runDesktopTranscoding(
    _TranscodingTask task,
    List<String> args, {
    bool waitForComplete = false,
  }) async {
    if (_ffmpegPath == null) {
      task.isRunning = false;
      task.error = 'FFmpeg 不可用';
      return;
    }

    try {
      // 执行 FFmpeg（使用已检测到的路径）
      final process = await Process.start(_ffmpegPath!, args);
      task.process = process;

      // 收集 stderr 输出用于错误诊断
      final stderrBuffer = StringBuffer();
      var hasStartedOutput = false;

      // 解析进度输出
      process.stderr.transform(const SystemEncoding().decoder).listen((line) {
        stderrBuffer.write(line);
        _parseProgress(task, line);

        // 检查是否开始输出视频数据
        if (line.contains('frame=') && !hasStartedOutput) {
          hasStartedOutput = true;
          logger.d('ClientTranscoding: 开始输出视频帧');
        }
      });

      if (waitForComplete) {
        // 等待完整转码完成
        final exitCode = await process.exitCode;
        _handleExitCode(task, exitCode, stderrBuffer);
      } else {
        // 流式转码：等待输出文件有足够数据就返回
        final outputFile = File(task.outputPath);
        const minFileSize = 2 * 1024 * 1024; // 至少 2MB 缓冲
        const maxWaitTime = Duration(seconds: 30);
        const checkInterval = Duration(milliseconds: 500);

        final startTime = DateTime.now();
        var fileReady = false;

        while (DateTime.now().difference(startTime) < maxWaitTime) {
          await Future<void>.delayed(checkInterval);

          // 检查进程是否已退出（表示转码失败）
          final exitCode = await process.exitCode.timeout(
            Duration.zero,
            onTimeout: () => -1, // 仍在运行
          );

          if (exitCode != -1) {
            // 进程已退出
            _handleExitCode(task, exitCode, stderrBuffer);
            return;
          }

          // 检查输出文件大小
          if (await outputFile.exists()) {
            final size = await outputFile.length();
            if (size >= minFileSize) {
              logger.i('ClientTranscoding: 流式输出就绪，文件大小: ${size ~/ 1024}KB');
              fileReady = true;
              break;
            }
          }
        }

        if (fileReady) {
          // 文件已有足够数据，可以开始播放
          // 注意：转码仍在后台继续
          task.isCompleted = true; // 标记为"可播放"状态
          logger.i('ClientTranscoding: 流式转码已就绪 ${task.outputPath}');

          // 后台监控转码进程
          AppError.fireAndForget(
            process.exitCode.then((exitCode) {
              if (exitCode == 0) {
                logger.i('ClientTranscoding: 后台转码完成 ${task.outputPath}');
              } else {
                logger.w('ClientTranscoding: 后台转码异常退出 $exitCode');
              }
              task.isRunning = false;
            }),
            action: 'clientTranscoding.monitorExitCode',
          );
        } else {
          // 等待超时，检查当前状态
          task.isRunning = false;
          task.error = '等待转码输出超时';
          logger.e('ClientTranscoding: 等待转码输出超时');
          logger.e('ClientTranscoding: FFmpeg 输出:\n${stderrBuffer.toString().length > 1000 ? stderrBuffer.toString().substring(stderrBuffer.toString().length - 1000) : stderrBuffer.toString()}');
          process.kill();
        }
      }
    } catch (e, st) {
      task.isRunning = false;
      task.error = e.toString();
      AppError.handle(e, st, 'desktopTranscoding');
    }
  }

  /// 处理 FFmpeg 退出码
  void _handleExitCode(_TranscodingTask task, int exitCode, StringBuffer stderrBuffer) {
    if (exitCode == 0) {
      task.isRunning = false;
      task.isCompleted = true;
      logger.i('ClientTranscoding: 转码完成 ${task.outputPath}');
    } else {
      task.isRunning = false;
      // 获取最后 500 字符的错误输出
      final stderrOutput = stderrBuffer.toString();
      final errorSnippet = stderrOutput.length > 500
          ? stderrOutput.substring(stderrOutput.length - 500)
          : stderrOutput;
      task.error = '转码失败，退出码: $exitCode';
      logger.e('ClientTranscoding: 转码失败 $exitCode');
      logger.e('ClientTranscoding: FFmpeg 错误输出:\n$errorSnippet');
    }
  }

  /// 添加视频编码器参数（根据平台选择硬件加速）
  void _addVideoEncoderArgs(List<String> args) {
    // 如果之前硬件编码失败，直接使用软件编码
    if (_hwEncoderFailed) {
      _addSoftwareEncoderArgs(args);
      return;
    }

    if (Platform.isMacOS || Platform.isIOS) {
      // Apple 平台：VideoToolbox 硬件编码
      // macOS 使用打包的 FFmpeg，iOS 使用 FFmpegKit，都支持 VideoToolbox
      args.addAll(['-c:v', 'h264_videotoolbox']);
      args.addAll(['-profile:v', 'high']);
      args.addAll(['-level', '4.1']); // Level 4.1 支持 1080p
      // VideoToolbox 特定优化
      args.addAll(['-realtime', '1']); // 实时编码模式
      args.addAll(['-allow_sw', '1']); // 允许软件回退
      logger.d('ClientTranscoding: 使用 VideoToolbox 硬件编码');
    } else if (Platform.isAndroid) {
      // Android：MediaCodec 硬件编码
      // FFmpegKit 内置支持 MediaCodec
      args.addAll(['-c:v', 'h264_mediacodec']);
      // MediaCodec 可能需要特定的像素格式
      logger.d('ClientTranscoding: 使用 MediaCodec 硬件编码');
    } else if (Platform.isWindows) {
      // Windows：尝试多种硬件编码器
      final encoder = _detectedHwEncoder ?? _detectWindowsHwEncoder();
      if (encoder.isNotEmpty) {
        args.addAll(['-c:v', encoder]);
        _addHwEncoderOptions(args, encoder);
        logger.d('ClientTranscoding: 使用 $encoder 硬件编码');
      } else {
        _addSoftwareEncoderArgs(args);
      }
    } else if (Platform.isLinux) {
      // Linux：尝试 VAAPI 或 NVENC
      final encoder = _detectedHwEncoder ?? _detectLinuxHwEncoder();
      if (encoder.isNotEmpty) {
        args.addAll(['-c:v', encoder]);
        _addHwEncoderOptions(args, encoder);
        logger.d('ClientTranscoding: 使用 $encoder 硬件编码');
      } else {
        _addSoftwareEncoderArgs(args);
      }
    } else {
      // 其他平台：软件编码
      _addSoftwareEncoderArgs(args);
    }
  }

  /// 添加软件编码器参数
  void _addSoftwareEncoderArgs(List<String> args) {
    args.addAll(['-c:v', 'libx264']);
    args.addAll(['-preset', 'ultrafast']); // 最快速度
    args.addAll(['-tune', 'zerolatency']); // 低延迟
    logger.d('ClientTranscoding: 使用 libx264 软件编码');
  }

  /// 添加硬件编码器特定选项
  void _addHwEncoderOptions(List<String> args, String encoder) {
    if (encoder.contains('nvenc')) {
      // NVIDIA NVENC 选项
      args.addAll(['-preset', 'p1']); // 最快预设
      args.addAll(['-tune', 'll']); // 低延迟
      args.addAll(['-rc', 'vbr']); // 可变码率
    } else if (encoder.contains('qsv')) {
      // Intel Quick Sync 选项
      args.addAll(['-preset', 'veryfast']);
      args.addAll(['-look_ahead', '0']); // 禁用前瞻减少延迟
    } else if (encoder.contains('amf')) {
      // AMD AMF 选项
      args.addAll(['-quality', 'speed']);
      args.addAll(['-rc', 'vbr_latency']);
    } else if (encoder.contains('vaapi')) {
      // VAAPI 选项
      args.addAll(['-vaapi_device', '/dev/dri/renderD128']);
      // VAAPI 需要特定的滤镜来处理格式转换
    }
  }

  /// 检测 Windows 平台可用的硬件编码器
  String _detectWindowsHwEncoder() {
    if (_detectedHwEncoder != null) return _detectedHwEncoder!;

    // Windows 硬件编码器优先级：NVENC > QSV > AMF > 软件
    // 注意：这里假设使用系统 FFmpeg，FFmpegKit 在 Windows 上可能不可用
    final encoders = ['h264_nvenc', 'h264_qsv', 'h264_amf'];

    for (final encoder in encoders) {
      if (_checkEncoderAvailable(encoder)) {
        _detectedHwEncoder = encoder;
        logger.i('ClientTranscoding: Windows 检测到硬件编码器: $encoder');
        return encoder;
      }
    }

    _detectedHwEncoder = '';
    logger.w('ClientTranscoding: Windows 未检测到硬件编码器，使用软件编码');
    return '';
  }

  /// 检测 Linux 平台可用的硬件编码器
  String _detectLinuxHwEncoder() {
    if (_detectedHwEncoder != null) return _detectedHwEncoder!;

    // Linux 硬件编码器优先级：NVENC > VAAPI > 软件
    final encoders = ['h264_nvenc', 'h264_vaapi'];

    for (final encoder in encoders) {
      if (_checkEncoderAvailable(encoder)) {
        _detectedHwEncoder = encoder;
        logger.i('ClientTranscoding: Linux 检测到硬件编码器: $encoder');
        return encoder;
      }
    }

    _detectedHwEncoder = '';
    logger.w('ClientTranscoding: Linux 未检测到硬件编码器，使用软件编码');
    return '';
  }

  /// 检查编码器是否可用
  bool _checkEncoderAvailable(String encoder) {
    if (_ffmpegPath == null) return false;

    try {
      // 运行 ffmpeg -encoders 并检查输出
      final result = Process.runSync(
        _ffmpegPath!,
        ['-encoders'],
        stdoutEncoding: const SystemEncoding(),
        stderrEncoding: const SystemEncoding(),
      );

      final output = result.stdout.toString();
      return output.contains(encoder);
    } catch (e) {
      logger.w('ClientTranscoding: 检查编码器 $encoder 失败: $e');
      return false;
    }
  }

  /// 标记硬件编码失败，后续使用软件编码
  void _markHwEncoderFailed() {
    if (!_hwEncoderFailed) {
      _hwEncoderFailed = true;
      logger.w('ClientTranscoding: 硬件编码失败，切换到软件编码');
    }
  }

  /// 检测是否是编码器相关的错误
  bool _isEncoderError(String logs) {
    final lowerLogs = logs.toLowerCase();
    // 常见的硬件编码器错误关键词
    return lowerLogs.contains('encoder') ||
        lowerLogs.contains('videotoolbox') ||
        lowerLogs.contains('mediacodec') ||
        lowerLogs.contains('nvenc') ||
        lowerLogs.contains('qsv') ||
        lowerLogs.contains('vaapi') ||
        lowerLogs.contains('amf') ||
        lowerLogs.contains('hardware') ||
        lowerLogs.contains('h264_') ||
        lowerLogs.contains('hevc_') ||
        lowerLogs.contains('no device') ||
        lowerLogs.contains('device not found') ||
        lowerLogs.contains('unsupported codec');
  }

  /// 构建 FFmpeg 参数
  List<String> _buildFfmpegArgs(_TranscodingTask task) {
    final args = <String>[
      '-y', // 覆盖输出文件
    ];

    // 起始位置 - 放在 -i 之前实现输入文件快速跳转（input seeking）
    // 这样 FFmpeg 会快速跳过前面的内容，不需要解码
    if (task.startPosition != null && task.startPosition! > Duration.zero) {
      args.addAll(['-ss', '${task.startPosition!.inSeconds}']);
      logger.d('ClientTranscoding: 从 ${task.startPosition!.inSeconds}s 开始转码');
    }

    // 输入文件
    args.addAll(['-i', task.inputPath]);

    // 视频编码参数 - 根据平台使用硬件加速
    _addVideoEncoderArgs(args);

    // 通用设置：确保 8-bit 标准像素格式（某些硬件编码器需要）
    args.addAll(['-pix_fmt', 'yuv420p']);

    // 分辨率缩放
    if (!task.quality.isOriginal && task.quality.maxWidth != null && task.quality.maxHeight != null) {
      args.addAll([
        '-vf',
        'scale=${task.quality.maxWidth}:${task.quality.maxHeight}:force_original_aspect_ratio=decrease',
      ]);
    }

    // 码率
    if (task.quality.estimatedBitrate != null) {
      args.addAll(['-b:v', '${task.quality.estimatedBitrate}']);
    }

    // 音频编码
    args.addAll(['-c:a', 'aac']); // AAC 编码
    args.addAll(['-b:a', '128k']); // 128kbps 音频

    // 选择音轨
    if (task.audioStreamIndex != null) {
      args.addAll(['-map', '0:v:0', '-map', '0:a:${task.audioStreamIndex}']);
    }

    // 字幕烧录
    if (task.subtitleStreamIndex != null && task.subtitleStreamIndex! >= 0) {
      // 需要处理字幕烧录，这里简化处理
      args.addAll(['-sn']); // 暂时不处理字幕
    } else {
      args.addAll(['-sn']); // 不包含字幕
    }

    // 输出格式 - 使用 MKV 格式支持流式播放（边转边播）
    // MKV 格式可以在转码过程中被播放，且 MPV 能正确处理增长中的文件
    args.addAll(['-f', 'matroska']);

    // 输出文件
    args.add(task.outputPath);

    return args;
  }

  /// 解析 FFmpeg 进度输出
  void _parseProgress(_TranscodingTask task, String line) {
    // 解析时间戳: time=00:01:23.45
    final timeMatch = RegExp(r'time=(\d+):(\d+):(\d+\.\d+)').firstMatch(line);
    if (timeMatch != null) {
      final hours = int.parse(timeMatch.group(1)!);
      final minutes = int.parse(timeMatch.group(2)!);
      final seconds = double.parse(timeMatch.group(3)!);

      final currentSeconds = hours * 3600 + minutes * 60 + seconds;
      // 这里需要知道总时长才能计算进度
      // 暂时只更新当前时间
      task.currentTime = Duration(milliseconds: (currentSeconds * 1000).round());
    }

    // 解析速度: speed=1.5x
    final speedMatch = RegExp(r'speed=\s*(\d+\.?\d*)x').firstMatch(line);
    if (speedMatch != null) {
      task.speed = '${speedMatch.group(1)}x';
    }
  }

  /// 清理临时文件
  Future<void> _cleanupTempFiles() async {
    if (_tempDir == null) return;

    try {
      final files = _tempDir!.listSync();
      for (final file in files) {
        if (file is File && file.path.contains('transcoded_')) {
          await file.delete();
        }
      }
    } catch (e, st) {
      AppError.ignore(e, st, '清理临时文件失败');
    }
  }

  /// 取消指定的转码任务
  Future<void> cancelTask(String taskId) async {
    final task = _tasks.remove(taskId);
    if (task != null) {
      task.cancel();

      // 删除输出文件
      final outputFile = File(task.outputPath);
      if (await outputFile.exists()) {
        await outputFile.delete();
      }
    }
  }
}

/// 转码任务内部类
class _TranscodingTask {
  _TranscodingTask({
    required this.taskId,
    required this.inputPath,
    required this.outputPath,
    required this.quality,
    this.startPosition,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
  });

  final String taskId;
  final String inputPath;
  final String outputPath;
  final VideoQuality quality;
  final Duration? startPosition;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;

  /// 桌面端 Process
  Process? process;

  /// 移动端 FFmpegSession
  FFmpegSession? ffmpegSession;

  bool isRunning = false;
  bool isCompleted = false;
  String? error;

  double progress = 0.0;
  String? speed;
  Duration? eta;
  Duration? currentTime;
  Duration? totalDuration;

  void cancel() {
    isRunning = false;

    // 取消桌面端 Process
    process?.kill();
    process = null;

    // 取消移动端 FFmpegSession
    if (ffmpegSession != null) {
      FFmpegKit.cancel(ffmpegSession!.getSessionId());
      ffmpegSession = null;
    }
  }
}
