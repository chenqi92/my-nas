import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:my_nas/core/network/resolved_http_client.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 海报压缩配置
class _PosterCompressionConfig {
  const _PosterCompressionConfig({
    required this.maxWidth,
    required this.maxHeight,
    required this.jpegQuality,
    required this.compressThreshold,
  });

  final int maxWidth;
  final int maxHeight;
  final int jpegQuality;
  final int compressThreshold;
}

/// 视频海报缓存服务
///
/// 在刮削时主动下载海报到本地，支持离线显示
/// 自动压缩大尺寸海报以节省存储空间
///
/// 优化策略：
/// - 根据平台自适应压缩参数（桌面端高质量，移动端更激进压缩）
/// - 桌面端屏幕大，使用更高质量和更大尺寸
/// - 移动端存储有限，使用更高压缩率
class VideoPosterCacheService {
  factory VideoPosterCacheService() => _instance ??= VideoPosterCacheService._();
  VideoPosterCacheService._();

  static VideoPosterCacheService? _instance;

  /// 桌面端配置（macOS, Windows, Linux）
  /// - 更大尺寸：500x750（适合大屏显示）
  /// - 更高质量：85%（细节保留更好）
  /// - 更宽松阈值：200KB
  static const _desktopConfig = _PosterCompressionConfig(
    maxWidth: 500,
    maxHeight: 750,
    jpegQuality: 85,
    compressThreshold: 200 * 1024, // 200KB
  );

  /// 移动端配置（iOS, Android）
  /// - 更小尺寸：400x600（移动端足够）
  /// - 更低质量：70%（视觉差异不明显但大小减少显著）
  /// - 更积极压缩：80KB
  static const _mobileConfig = _PosterCompressionConfig(
    maxWidth: 400,
    maxHeight: 600,
    jpegQuality: 70,
    compressThreshold: 80 * 1024, // 80KB
  );

  /// 获取当前平台的压缩配置
  _PosterCompressionConfig get _config {
    if (Platform.isAndroid || Platform.isIOS) {
      return _mobileConfig;
    }
    return _desktopConfig;
  }

  /// 是否为桌面平台
  static bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  Directory? _cacheDir;
  final _downloadingTasks = <String, Future<String?>>{};

  /// 初始化服务
  Future<void> init() async {
    if (_cacheDir != null) return;
    try {
      final appDir = await getApplicationSupportDirectory();
      _cacheDir = Directory(p.join(appDir.path, 'video_posters'));
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
      logger.i('VideoPosterCacheService: 初始化完成，缓存目录: ${_cacheDir!.path}');
    } on Exception catch (e) {
      logger.e('VideoPosterCacheService: 初始化失败', e);
    }
  }

  /// 生成缓存键（基于 sourceId 和 filePath）
  String _generateCacheKey(String sourceId, String filePath) {
    final combined = '$sourceId:$filePath';
    // 使用简单的哈希生成文件名
    final hash = combined.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0');
    return hash;
  }

  /// 获取缓存的海报路径
  String? getCachedPosterPath(String sourceId, String filePath) {
    if (_cacheDir == null) return null;
    final cacheKey = _generateCacheKey(sourceId, filePath);

    // 检查常见图片格式
    for (final ext in ['jpg', 'png', 'webp']) {
      final posterPath = p.join(_cacheDir!.path, '$cacheKey.$ext');
      final file = File(posterPath);
      if (file.existsSync()) {
        return posterPath;
      }
    }
    return null;
  }

  /// 获取缓存的海报 URL (file:// 格式)
  String? getCachedPosterUrl(String sourceId, String filePath) {
    final path = getCachedPosterPath(sourceId, filePath);
    if (path != null) {
      return Uri.file(path).toString();
    }
    return null;
  }

  /// 下载并缓存海报
  ///
  /// [sourceId] 源 ID
  /// [filePath] 视频文件路径（用于生成缓存键）
  /// [posterUrl] 海报 URL（TMDB 或 NAS 的 HTTP URL）
  /// [fileSystem] 可选的文件系统接口，用于从 NAS 下载
  Future<String?> downloadAndCachePoster({
    required String sourceId,
    required String filePath,
    required String posterUrl,
    NasFileSystem? fileSystem,
  }) async {
    if (_cacheDir == null) {
      await init();
      if (_cacheDir == null) return null;
    }

    // 检查缓存
    final cachedUrl = getCachedPosterUrl(sourceId, filePath);
    if (cachedUrl != null) {
      logger.d('VideoPosterCacheService: 使用缓存海报 $cachedUrl');
      return cachedUrl;
    }

    // 防止重复下载
    final cacheKey = _generateCacheKey(sourceId, filePath);
    if (_downloadingTasks.containsKey(cacheKey)) {
      logger.d('VideoPosterCacheService: 等待正在下载的任务 $cacheKey');
      return _downloadingTasks[cacheKey];
    }

    // 开始下载任务
    final task = _doDownloadPoster(
      cacheKey: cacheKey,
      posterUrl: posterUrl,
      fileSystem: fileSystem,
    );
    _downloadingTasks[cacheKey] = task;

    try {
      return await task;
    } finally {
      // ignore: unawaited_futures - 仅移除 Map 中的引用，无需关心返回值
      _downloadingTasks.remove(cacheKey);
    }
  }

  Future<String?> _doDownloadPoster({
    required String cacheKey,
    required String posterUrl,
    NasFileSystem? fileSystem,
  }) async {
    try {
      Uint8List? imageData;

      // 根据 URL 类型选择下载方式
      if (posterUrl.startsWith('http://') || posterUrl.startsWith('https://')) {
        // HTTP(S) URL - 直接下载
        imageData = await _downloadFromHttp(posterUrl);
      } else if (fileSystem != null) {
        // 使用文件系统接口下载（用于 NAS 本地文件）
        imageData = await _downloadFromFileSystem(posterUrl, fileSystem);
      }

      if (imageData == null || imageData.isEmpty) {
        logger.w('VideoPosterCacheService: 下载海报失败，数据为空 $posterUrl');
        return null;
      }

      // 压缩海报（如果需要）
      final compressedData = await _compressImageIfNeeded(imageData);

      // 压缩后统一保存为 JPEG
      final cachePath = p.join(_cacheDir!.path, '$cacheKey.jpg');
      final file = File(cachePath);
      await file.writeAsBytes(compressedData);

      final originalSize = imageData.length;
      final compressedSize = compressedData.length;
      if (originalSize != compressedSize) {
        logger.d(
          'VideoPosterCacheService: 海报已压缩 '
          '${_formatSize(originalSize)} -> ${_formatSize(compressedSize)}',
        );
      }

      final fileUrl = Uri.file(cachePath).toString();
      logger.d('VideoPosterCacheService: 海报已缓存 $fileUrl');
      return fileUrl;
    } on Exception catch (e) {
      logger.e('VideoPosterCacheService: 下载海报失败 $posterUrl', e);
      return null;
    }
  }

  /// 从 HTTP(S) URL 下载图片
  Future<Uint8List?> _downloadFromHttp(String url) async {
    try {
      final response = await ResolvedHttpClient.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'MyNAS/1.0',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      logger.w('VideoPosterCacheService: HTTP 下载失败 ${response.statusCode}');
      return null;
    } on Exception catch (e) {
      logger.e('VideoPosterCacheService: HTTP 下载异常', e);
      return null;
    }
  }

  /// 从 NAS 文件系统下载图片
  Future<Uint8List?> _downloadFromFileSystem(
    String path,
    NasFileSystem fileSystem,
  ) async {
    try {
      final stream = await fileSystem.getFileStream(path);
      final chunks = <int>[];
      await for (final chunk in stream) {
        chunks.addAll(chunk);
      }
      return Uint8List.fromList(chunks);
    } on Exception catch (e) {
      logger.e('VideoPosterCacheService: 文件系统下载异常', e);
      return null;
    }
  }

  /// 压缩图片（如果需要）
  ///
  /// 压缩条件：
  /// 1. 原始大小超过压缩阈值
  /// 2. 图片尺寸超过最大尺寸限制
  ///
  /// 压缩参数根据平台自适应：
  /// - 桌面端：更大尺寸、更高质量
  /// - 移动端：更小尺寸、更激进压缩
  Future<Uint8List> _compressImageIfNeeded(Uint8List imageData) async {
    final config = _config;

    // 小于阈值直接返回
    if (imageData.length < config.compressThreshold) {
      return imageData;
    }

    try {
      // 解码图片
      final image = img.decodeImage(imageData);
      if (image == null) {
        logger.w('VideoPosterCacheService: 无法解码图片，跳过压缩');
        return imageData;
      }

      var needsResize = false;
      var targetWidth = image.width;
      var targetHeight = image.height;

      // 检查是否需要缩放
      if (image.width > config.maxWidth || image.height > config.maxHeight) {
        needsResize = true;

        // 计算缩放比例，保持宽高比
        final widthRatio = config.maxWidth / image.width;
        final heightRatio = config.maxHeight / image.height;
        final ratio = widthRatio < heightRatio ? widthRatio : heightRatio;

        targetWidth = (image.width * ratio).round();
        targetHeight = (image.height * ratio).round();
      }

      // 缩放图片（如果需要）
      final resizedImage = needsResize
          ? img.copyResize(
              image,
              width: targetWidth,
              height: targetHeight,
              interpolation: img.Interpolation.linear,
            )
          : image;

      // 编码为 JPEG
      final compressedData = img.encodeJpg(resizedImage, quality: config.jpegQuality);

      // 如果压缩后反而更大，返回原数据
      if (compressedData.length >= imageData.length && !needsResize) {
        return imageData;
      }

      logger.d(
        'VideoPosterCacheService: 海报已压缩 (${_isDesktop ? "桌面" : "移动"}端配置) '
        '${image.width}x${image.height} -> ${targetWidth}x$targetHeight, '
        'quality: ${config.jpegQuality}%',
      );

      return Uint8List.fromList(compressedData);
    } on Exception catch (e) {
      logger.w('VideoPosterCacheService: 压缩失败，使用原图', e);
      return imageData;
    }
  }

  /// 格式化文件大小
  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// 删除指定视频的海报缓存
  Future<void> deleteCachedPoster(String sourceId, String filePath) async {
    final path = getCachedPosterPath(sourceId, filePath);
    if (path != null) {
      try {
        await File(path).delete();
        logger.d('VideoPosterCacheService: 已删除缓存海报 $path');
      } on Exception catch (e) {
        logger.w('VideoPosterCacheService: 删除缓存失败', e);
      }
    }
  }

  /// 删除指定源的所有海报缓存
  Future<void> deleteBySourceId(String sourceId) async {
    // 由于缓存键是基于 sourceId + filePath 的哈希，
    // 无法直接按 sourceId 过滤，需要清理整个缓存
    // 这里我们选择不实现，让缓存自然过期
    logger.d('VideoPosterCacheService: deleteBySourceId 暂不实现');
  }

  /// 获取缓存大小（字节）
  Future<int> getCacheSize() async {
    if (_cacheDir == null || !await _cacheDir!.exists()) {
      return 0;
    }

    var totalSize = 0;
    await for (final entity in _cacheDir!.list()) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }
    return totalSize;
  }

  /// 清除所有缓存
  Future<void> clearAll() async {
    if (_cacheDir == null || !await _cacheDir!.exists()) {
      return;
    }

    await for (final entity in _cacheDir!.list()) {
      if (entity is File) {
        await entity.delete();
      }
    }
    logger.i('VideoPosterCacheService: 缓存已清除');
  }

  /// 获取缓存文件数量
  Future<int> getCacheCount() async {
    if (_cacheDir == null || !await _cacheDir!.exists()) {
      return 0;
    }

    var count = 0;
    await for (final entity in _cacheDir!.list()) {
      if (entity is File) {
        count++;
      }
    }
    return count;
  }
}
