import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/local_file_uri.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 视频路径工具类
///
/// 处理不同来源的视频路径转换
class VideoPathUtils {
  VideoPathUtils._();

  /// 将视频 URL 转换为可用于缩略图生成的路径
  ///
  /// 处理以下情况：
  /// - file:// URI（本地文件）- 转换为本地文件路径
  /// - http/https URL（远程文件）- 直接返回，media_kit 可处理
  /// - smb:// URI（SMB 共享）- 需要流式下载，返回 null
  /// - webdav:// URI（WebDAV）- 需要流式下载，返回 null
  /// - 本地路径（非 URI）- 直接返回
  static String? convertToLocalPath(String videoUrl) {
    if (videoUrl.isEmpty) return null;

    // 处理 file:// URI
    if (videoUrl.startsWith('file://')) {
      final localPath = localPathFromFileUri(videoUrl);
      logger.d('VideoPathUtils: file URI 转换为本地路径: $videoUrl -> $localPath');
      return localPath;
    }

    // HTTP/HTTPS URL - media_kit 可以直接处理
    if (videoUrl.startsWith('http://') || videoUrl.startsWith('https://')) {
      return videoUrl;
    }

    // SMB URI - 需要通过流式下载处理
    if (isSmbUri(videoUrl)) {
      return null;
    }

    // WebDAV URI - 需要通过流式下载处理
    if (isWebDavUri(videoUrl)) {
      return null;
    }

    // 其他情况假设是本地路径
    return videoUrl;
  }

  /// 检查是否是 SMB URI
  static bool isSmbUri(String path) => path.startsWith('smb://');

  /// 检查是否是 WebDAV URI
  static bool isWebDavUri(String path) => path.startsWith('webdav://');

  /// 检查是否需要流式下载（SMB、WebDAV 等不支持直接 URL 访问的协议）
  static bool needsStreamDownload(String path) =>
      isSmbUri(path) || isWebDavUri(path);

  /// 检查路径是否是本地文件（可直接访问）
  static bool isLocalFile(String path) {
    if (path.startsWith('file://')) {
      final localPath = convertToLocalPath(path);
      if (localPath != null) {
        return File(localPath).existsSync();
      }
      return false;
    }

    // 这些协议不是本地文件
    if (path.startsWith('http://') ||
        path.startsWith('https://') ||
        isSmbUri(path) ||
        isWebDavUri(path)) {
      return false;
    }

    // 假设是本地路径
    return File(path).existsSync();
  }

  /// 检查路径是否是 HTTP/HTTPS URL
  static bool isHttpUrl(String path) =>
      path.startsWith('http://') || path.startsWith('https://');
}

/// 视频缩略图服务
///
/// 使用 media_kit 提取视频帧生成缩略图，无需依赖系统 FFmpeg
/// 支持所有平台：Windows/macOS/iOS/Android/Linux
class VideoThumbnailService {
  factory VideoThumbnailService() => _instance ??= VideoThumbnailService._();
  VideoThumbnailService._();

  static VideoThumbnailService? _instance;

  Directory? _cacheDir;
  Directory? _progressCacheDir;
  final _generatingTasks = <String, Future<String?>>{};

  /// 初始化服务
  Future<void> init() async {
    if (_cacheDir != null) return;
    try {
      final appDir = await getApplicationSupportDirectory();
      _cacheDir = Directory(p.join(appDir.path, 'video_thumbnails'));
      _progressCacheDir = Directory(p.join(appDir.path, 'progress_thumbnails'));
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
      if (!await _progressCacheDir!.exists()) {
        await _progressCacheDir!.create(recursive: true);
      }
      logger.i('VideoThumbnailService: 初始化完成，缓存目录: ${_cacheDir!.path}');
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'initVideoThumbnailService');
    }
  }

  /// 获取缓存的缩略图路径
  String? getCachedThumbnailPath(String videoPath) {
    if (_cacheDir == null) return null;
    final cacheKey = _generateCacheKey(videoPath);
    final thumbnailPath = p.join(_cacheDir!.path, '$cacheKey.jpg');
    final file = File(thumbnailPath);
    if (file.existsSync()) {
      return thumbnailPath;
    }
    return null;
  }

  /// 获取缓存的缩略图 URL (file:// 格式)
  String? getCachedThumbnailUrl(String videoPath) {
    final path = getCachedThumbnailPath(videoPath);
    if (path != null) {
      return Uri.file(path).toString();
    }
    return null;
  }

  /// 从视频 URL 生成缩略图
  ///
  /// [videoUrl] 视频的 URL（可以是 http/https/file/smb 等）
  /// [videoPath] 视频在 NAS 上的路径（用于生成缓存键和流式下载）
  /// [timeMs] 截取位置（毫秒，默认 5000 即 5 秒位置）
  /// [fileSystem] 可选的文件系统接口，用于 SMB 等需要流式下载的协议
  Future<String?> generateThumbnail({
    required String videoUrl,
    required String videoPath,
    int timeMs = 5000,
    NasFileSystem? fileSystem,
  }) async {
    if (_cacheDir == null) {
      await init();
      if (_cacheDir == null) return null;
    }

    // 检查缓存
    final cachedPath = getCachedThumbnailPath(videoPath);
    if (cachedPath != null) {
      logger.d('VideoThumbnailService: 使用缓存缩略图 $cachedPath');
      return cachedPath;
    }

    // 防止重复生成
    final cacheKey = _generateCacheKey(videoPath);
    if (_generatingTasks.containsKey(cacheKey)) {
      logger.d('VideoThumbnailService: 等待正在生成的任务 $cacheKey');
      return _generatingTasks[cacheKey];
    }

    // 开始生成任务
    final task = _doGenerateThumbnail(
      videoUrl: videoUrl,
      videoPath: videoPath,
      cacheKey: cacheKey,
      timeMs: timeMs,
      fileSystem: fileSystem,
    );
    _generatingTasks[cacheKey] = task;

    try {
      final result = await task;
      return result;
    } finally {
      await _generatingTasks.remove(cacheKey);
    }
  }

  Future<String?> _doGenerateThumbnail({
    required String videoUrl,
    required String videoPath,
    required String cacheKey,
    required int timeMs,
    NasFileSystem? fileSystem,
  }) async {
    String? tempFilePath;

    try {
      logger.d('VideoThumbnailService: 开始生成缩略图 $videoUrl');

      String? effectivePath;

      // 检查是否需要流式下载（SMB、WebDAV 等协议）
      final needsDownload =
          VideoPathUtils.needsStreamDownload(videoUrl) && fileSystem != null;

      if (needsDownload) {
        final protocol = VideoPathUtils.isSmbUri(videoUrl) ? 'SMB' : 'WebDAV';
        logger.d('VideoThumbnailService: 使用流式下载处理 $protocol 视频');

        // 渐进式下载：从小到大尝试不同的下载大小
        for (
          var sizeLevel = 0;
          sizeLevel < _downloadSizes.length;
          sizeLevel++
        ) {
          // 清理上一次的临时文件
          if (tempFilePath != null) {
            try {
              await File(tempFilePath).delete();
            } on Exception catch (e, st) {
              AppError.ignore(
                e,
                st,
                appL10n.videoThumbnailServiceCleanupPreviousFileFailed,
              );
            }
          }

          tempFilePath = await _downloadVideoForThumbnail(
            fileSystem: fileSystem,
            filePath: videoPath,
            cacheKey: cacheKey,
            sizeLevel: sizeLevel,
          );

          if (tempFilePath == null) {
            logger.w('VideoThumbnailService: $protocol 视频下载失败');
            return null;
          }

          // 尝试生成缩略图
          final result = await _captureFrameWithMediaKit(tempFilePath, timeMs);
          if (result != null) {
            // 成功，保存到缓存目录
            final thumbnailPath = p.join(_cacheDir!.path, '$cacheKey.jpg');
            await File(thumbnailPath).writeAsBytes(result);
            logger.i(
              'VideoThumbnailService: 缩略图生成成功 $thumbnailPath (下载 ${_downloadSizes[sizeLevel] ~/ 1024 ~/ 1024}MB)',
            );
            return thumbnailPath;
          }

          // 如果不是最后一次尝试，继续下载更大的片段
          if (sizeLevel < _downloadSizes.length - 1) {
            logger.d(
              'VideoThumbnailService: 下载 ${_downloadSizes[sizeLevel] ~/ 1024 ~/ 1024}MB 不足以生成缩略图，尝试更大的片段',
            );
          }
        }

        logger.w('VideoThumbnailService: 所有下载大小都无法生成缩略图');
        return null;
      } else {
        // 转换路径：将 file:// URI 转换为本地路径
        effectivePath = VideoPathUtils.convertToLocalPath(videoUrl);
        if (effectivePath == null) {
          // 如果是需要流式下载的协议但没有提供 fileSystem，给出提示
          if (VideoPathUtils.needsStreamDownload(videoUrl)) {
            final protocol = VideoPathUtils.isSmbUri(videoUrl)
                ? 'SMB'
                : 'WebDAV';
            logger.w(
              'VideoThumbnailService: $protocol 路径需要提供 fileSystem 参数: $videoUrl',
            );
          } else {
            logger.w('VideoThumbnailService: 无法处理的视频路径: $videoUrl');
          }
          return null;
        }
      }

      logger.d('VideoThumbnailService: 使用路径: $effectivePath');

      // 使用 media_kit 提取帧
      final imageBytes = await _captureFrameWithMediaKit(effectivePath, timeMs);

      if (imageBytes == null) {
        logger.w('VideoThumbnailService: 提取帧失败');
        return null;
      }

      // 保存到缓存目录
      final thumbnailPath = p.join(_cacheDir!.path, '$cacheKey.jpg');
      await File(thumbnailPath).writeAsBytes(imageBytes);

      logger.i('VideoThumbnailService: 缩略图生成成功 $thumbnailPath');
      return thumbnailPath;
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'generateThumbnail', {
        'videoUrl': videoUrl,
        'videoPath': videoPath,
      });
      return null;
    } finally {
      // 清理临时文件
      if (tempFilePath != null) {
        try {
          final tempFile = File(tempFilePath);
          if (await tempFile.exists()) {
            await tempFile.delete();
            logger.d('VideoThumbnailService: 已清理临时文件 $tempFilePath');
          }
        } on Exception catch (e, st) {
          AppError.ignore(
            e,
            st,
            appL10n.videoThumbnailServiceCleanupTempFileFailed,
          );
        }
      }
    }
  }

  /// 使用 media_kit 从视频中提取帧
  ///
  /// 返回 JPEG 格式的图片字节数据
  Future<Uint8List?> _captureFrameWithMediaKit(
    String videoPath,
    int timeMs,
  ) async {
    Player? player;
    VideoController? controller;

    try {
      logger.d(
        'VideoThumbnailService: 使用 media_kit 提取帧: $videoPath @ ${timeMs}ms',
      );

      // 创建播放器实例
      player = Player(
        configuration: const PlayerConfiguration(
          // 静音
          muted: true,
          // 日志级别
          logLevel: MPVLogLevel.warn,
        ),
      );

      // 创建 VideoController 以确保视频帧被渲染
      // screenshot() 需要有渲染输出才能工作
      controller = VideoController(player);

      // 打开视频但不播放
      await player.open(Media(videoPath), play: false);

      // 等待视频加载完成（duration > 0）
      final durationCompleter = Completer<Duration>();
      StreamSubscription<Duration>? durationSubscription;

      durationSubscription = player.stream.duration.listen((duration) {
        if (duration > Duration.zero && !durationCompleter.isCompleted) {
          durationCompleter.complete(duration);
          durationSubscription?.cancel();
        }
      });

      // 设置超时
      final duration = await durationCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          durationSubscription?.cancel();
          throw TimeoutException(appL10n.videoThumbnailServiceLoadTimeout);
        },
      );

      logger.d('VideoThumbnailService: 视频时长: ${duration.inSeconds}s');

      // 确定截取位置（不超过视频时长的 90%）
      final maxTimeMs = (duration.inMilliseconds * 0.9).toInt();
      final seekTimeMs = timeMs.clamp(0, maxTimeMs);

      // Seek 到指定位置
      await player.seek(Duration(milliseconds: seekTimeMs));

      // 等待首帧渲染完成（带超时）
      try {
        await controller.waitUntilFirstFrameRendered.timeout(
          const Duration(seconds: 5),
        );
      } on TimeoutException {
        // 如果超时，继续尝试截图（可能已经渲染但事件未触发）
        logger.d('VideoThumbnailService: 等待首帧渲染超时，继续尝试截图');
      }

      // 额外等待确保帧完全渲染
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // 截取当前帧（JPEG 格式）
      final screenshot = await player.screenshot();

      if (screenshot == null || screenshot.isEmpty) {
        logger.w('VideoThumbnailService: screenshot 返回空数据');
        return null;
      }

      logger.d('VideoThumbnailService: 截图成功，大小: ${screenshot.length} bytes');
      return screenshot;
    } on TimeoutException catch (e, st) {
      AppError.ignore(
        e,
        st,
        appL10n.videoThumbnailServiceFrameExtractionTimeout,
      );
      return null;
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'captureFrameWithMediaKit', {
        'videoPath': videoPath,
      });
      return null;
    } finally {
      // 释放资源
      await player?.dispose();
    }
  }

  /// 下载视频片段的大小级别（渐进式下载）
  static const _downloadSizes = [
    2 * 1024 * 1024, // 2MB - 大多数视频足够
    5 * 1024 * 1024, // 5MB - 复杂编码的视频
    10 * 1024 * 1024, // 10MB - 最后尝试
  ];

  /// 下载视频的前几 MB 用于生成缩略图
  ///
  /// 对于 SMB、WebDAV 等需要流式访问的协议，采用渐进式下载策略：
  /// 1. 首先尝试下载 2MB（对于大多数视频足够提取帧）
  /// 2. 如果生成失败，增加到 5MB
  /// 3. 最后尝试 10MB
  ///
  /// 这样可以显著减少网络传输和存储占用
  Future<String?> _downloadVideoForThumbnail({
    required NasFileSystem fileSystem,
    required String filePath,
    required String cacheKey,
    int sizeLevel = 0,
  }) async {
    if (sizeLevel >= _downloadSizes.length) {
      logger.w('VideoThumbnailService: 已尝试所有下载大小级别，放弃');
      return null;
    }

    final downloadSize = _downloadSizes[sizeLevel];

    try {
      logger.d(
        'VideoThumbnailService: 开始下载视频片段 $filePath (${downloadSize ~/ 1024 ~/ 1024}MB)',
      );

      // 获取文件扩展名
      final ext = p.extension(filePath).toLowerCase();
      final tempPath = p.join(_cacheDir!.path, 'temp_$cacheKey$ext');

      // 使用范围请求只下载指定大小
      final stream = await fileSystem.getFileStream(
        filePath,
        range: FileRange(start: 0, end: downloadSize),
      );

      // 写入临时文件
      final tempFile = File(tempPath);
      final sink = tempFile.openWrite();

      var bytesWritten = 0;
      await for (final chunk in stream) {
        sink.add(chunk);
        bytesWritten += chunk.length;

        // 限制下载大小
        if (bytesWritten >= downloadSize) {
          break;
        }
      }

      await sink.flush();
      await sink.close();

      logger.d(
        'VideoThumbnailService: 视频片段下载完成, 大小: ${bytesWritten ~/ 1024}KB',
      );
      return tempPath;
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'downloadVideoForThumbnail', {
        'filePath': filePath,
      });
      return null;
    }
  }

  /// 从本地视频文件生成缩略图
  Future<String?> generateFromLocalFile({
    required String localPath,
    int timeMs = 5000,
  }) async {
    if (_cacheDir == null) {
      await init();
      if (_cacheDir == null) return null;
    }

    // 检查缓存
    final cachedPath = getCachedThumbnailPath(localPath);
    if (cachedPath != null) {
      return cachedPath;
    }

    try {
      final cacheKey = _generateCacheKey(localPath);

      // 转换路径：将 file:// URI 转换为本地路径
      final effectivePath = VideoPathUtils.convertToLocalPath(localPath);
      if (effectivePath == null) {
        logger.w('VideoThumbnailService: 无法处理的本地路径: $localPath');
        return null;
      }

      final imageBytes = await _captureFrameWithMediaKit(effectivePath, timeMs);

      if (imageBytes == null) {
        logger.w('VideoThumbnailService: 从本地文件提取帧失败');
        return null;
      }

      // 保存到缓存目录
      final thumbnailPath = p.join(_cacheDir!.path, '$cacheKey.jpg');
      await File(thumbnailPath).writeAsBytes(imageBytes);

      return thumbnailPath;
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'generateFromLocalFile', {'localPath': localPath});
      return null;
    }
  }

  /// 删除指定视频的缓存缩略图
  Future<void> deleteCached(String videoPath) async {
    final path = getCachedThumbnailPath(videoPath);
    if (path != null) {
      try {
        await File(path).delete();
      } on Exception catch (e, st) {
        AppError.ignore(e, st, appL10n.videoThumbnailServiceDeleteCacheFailed);
      }
    }
  }

  /// 清除所有缓存
  Future<void> clearAllCache() async {
    if (_cacheDir == null) return;
    try {
      if (await _cacheDir!.exists()) {
        await _cacheDir!.delete(recursive: true);
        await _cacheDir!.create(recursive: true);
      }
      if (_progressCacheDir != null && await _progressCacheDir!.exists()) {
        await _progressCacheDir!.delete(recursive: true);
        await _progressCacheDir!.create(recursive: true);
      }
      logger.i('VideoThumbnailService: 缓存已清除');
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'clearAllCacheThumbnails');
    }
  }

  // ==================== 进度截图相关方法 ====================

  /// 保存进度截图（从播放器截取的当前帧）
  ///
  /// [videoPath] 视频路径（用于生成缓存键）
  /// [imageBytes] 截图的字节数据（JPEG 格式）
  /// 返回保存后的文件路径
  Future<String?> saveProgressThumbnail({
    required String videoPath,
    required Uint8List imageBytes,
  }) async {
    if (_progressCacheDir == null) {
      await init();
      if (_progressCacheDir == null) return null;
    }

    try {
      final cacheKey = _generateCacheKey(videoPath);
      final thumbnailPath = p.join(_progressCacheDir!.path, '$cacheKey.jpg');

      await File(thumbnailPath).writeAsBytes(imageBytes);
      logger.d('VideoThumbnailService: 进度截图已保存 $thumbnailPath');
      return thumbnailPath;
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'saveProgressThumbnail', {'videoPath': videoPath});
      return null;
    }
  }

  /// 获取进度截图路径
  String? getProgressThumbnailPath(String videoPath) {
    if (_progressCacheDir == null) return null;
    final cacheKey = _generateCacheKey(videoPath);
    final thumbnailPath = p.join(_progressCacheDir!.path, '$cacheKey.jpg');
    final file = File(thumbnailPath);
    if (file.existsSync()) {
      return thumbnailPath;
    }
    return null;
  }

  /// 获取进度截图 URL (file:// 格式)
  String? getProgressThumbnailUrl(String videoPath) {
    final path = getProgressThumbnailPath(videoPath);
    if (path != null) {
      return Uri.file(path).toString();
    }
    return null;
  }

  /// 删除进度截图
  Future<void> deleteProgressThumbnail(String videoPath) async {
    final path = getProgressThumbnailPath(videoPath);
    if (path != null) {
      try {
        await File(path).delete();
        logger.d('VideoThumbnailService: 进度截图已删除 $path');
      } on Exception catch (e, st) {
        AppError.ignore(
          e,
          st,
          appL10n.videoThumbnailServiceDeleteProgressThumbnailFailed,
        );
      }
    }
  }

  /// 清除所有进度截图缓存
  Future<void> clearAllProgressCache() async {
    if (_progressCacheDir == null) return;
    try {
      if (await _progressCacheDir!.exists()) {
        await _progressCacheDir!.delete(recursive: true);
        await _progressCacheDir!.create(recursive: true);
      }
      logger.i('VideoThumbnailService: 进度截图缓存已清除');
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'clearAllProgressCache');
    }
  }

  /// 获取进度截图缓存大小（字节）
  Future<int> getProgressCacheSize() async {
    if (_progressCacheDir == null || !await _progressCacheDir!.exists()) {
      return 0;
    }
    var totalSize = 0;
    try {
      await for (final entity in _progressCacheDir!.list()) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
    } on Exception catch (e) {
      logger.w('VideoThumbnailService: 计算进度截图缓存大小失败', e);
    }
    return totalSize;
  }

  /// 获取缓存大小（字节）
  Future<int> getCacheSize() async {
    if (_cacheDir == null || !await _cacheDir!.exists()) return 0;
    var totalSize = 0;
    try {
      await for (final entity in _cacheDir!.list()) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
    } on Exception catch (e) {
      logger.w('VideoThumbnailService: 计算缓存大小失败', e);
    }
    return totalSize;
  }

  /// 生成缓存键
  String _generateCacheKey(String videoPath) =>
      videoPath.hashCode.toRadixString(16);
}
