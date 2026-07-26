import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/network/dio_client.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 海报类型
enum PosterType {
  /// 封面海报 (poster.jpg)
  poster,

  /// 背景图 (fanart.jpg)
  fanart,

  /// 横版海报 (banner.jpg)
  banner,

  /// 横版图 (thumb.jpg)
  thumb,
}

/// 远程海报下载和保存服务
///
/// 从 TMDB 下载海报图片并上传到远程目录
class RemotePosterService {
  RemotePosterService({Dio? dio})
      : _dio = dio == null
            ? DioClient.createTlsAware()
            : DioClient.configureTls(dio);

  final Dio _dio;

  /// 下载并保存海报到远程目录
  ///
  /// [fileSystem] 远程文件系统
  /// [videoDir] 视频所在目录
  /// [posterUrl] TMDB 海报 URL
  /// [type] 海报类型
  /// [videoFileName] 视频文件名（用于生成特定的海报文件名）
  ///
  /// 返回远程海报路径（用于设置 localPosterUrl），失败返回 null
  Future<String?> downloadAndSavePoster({
    required NasFileSystem fileSystem,
    required String videoDir,
    required String posterUrl,
    PosterType type = PosterType.poster,
    String? videoFileName,
  }) async {
    try {
      logger.d('RemotePosterService: 开始下载海报 $posterUrl');

      // 1. 下载海报图片
      final imageData = await _downloadImage(posterUrl);
      if (imageData == null || imageData.isEmpty) {
        logger.w('RemotePosterService: 下载海报失败，数据为空');
        return null;
      }

      logger.d('RemotePosterService: 海报下载成功，大小 ${imageData.length} bytes');

      // 2. 生成目标文件名
      final fileName = _getPosterFileName(type, videoFileName, posterUrl);
      final posterPath = videoDir.endsWith('/') ? '$videoDir$fileName' : '$videoDir/$fileName';

      // 3. 上传到远程目录
      logger.d('RemotePosterService: 上传海报到 $posterPath');
      await fileSystem.writeFile(posterPath, imageData);

      logger.i('RemotePosterService: 海报保存成功 $posterPath');
      return posterPath;
    } on Exception catch (e, st) {
      logger.w('RemotePosterService: 海报下载或保存失败', e, st);
      return null;
    }
  }

  /// 下载图片
  Future<Uint8List?> _downloadImage(String url) async {
    try {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        return Uint8List.fromList(response.data!);
      }
      return null;
    } on DioException catch (e) {
      logger.w('RemotePosterService: 下载图片失败 $url - ${e.message}');
      return null;
    }
  }

  /// 获取海报文件名
  String _getPosterFileName(PosterType type, String? videoFileName, String posterUrl) {
    // 从 URL 获取扩展名
    final extension = _getExtensionFromUrl(posterUrl) ?? 'jpg';

    switch (type) {
      case PosterType.poster:
        // 如果有视频文件名，使用 {videoname}-poster.jpg
        if (videoFileName != null && videoFileName.isNotEmpty) {
          final baseName = _removeExtension(videoFileName);
          return '$baseName-poster.$extension';
        }
        return 'poster.$extension';

      case PosterType.fanart:
        if (videoFileName != null && videoFileName.isNotEmpty) {
          final baseName = _removeExtension(videoFileName);
          return '$baseName-fanart.$extension';
        }
        return 'fanart.$extension';

      case PosterType.banner:
        return 'banner.$extension';

      case PosterType.thumb:
        return 'thumb.$extension';
    }
  }

  /// 从 URL 获取文件扩展名
  String? _getExtensionFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      final dotIndex = path.lastIndexOf('.');
      if (dotIndex > 0 && dotIndex < path.length - 1) {
        return path.substring(dotIndex + 1).toLowerCase();
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'URL 解析失败，无法提取扩展名');
    }
    return null;
  }

  /// 移除文件扩展名
  String _removeExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex > 0) {
      return fileName.substring(0, dotIndex);
    }
    return fileName;
  }

  /// 批量下载并保存多个图片
  ///
  /// [fileSystem] 远程文件系统
  /// [videoDir] 视频所在目录
  /// [images] 图片列表 (type -> url)
  /// [videoFileName] 视频文件名
  ///
  /// 返回成功保存的图片路径映射
  Future<Map<PosterType, String>> downloadAndSaveMultiple({
    required NasFileSystem fileSystem,
    required String videoDir,
    required Map<PosterType, String> images,
    String? videoFileName,
  }) async {
    final results = <PosterType, String>{};

    for (final entry in images.entries) {
      final path = await downloadAndSavePoster(
        fileSystem: fileSystem,
        videoDir: videoDir,
        posterUrl: entry.value,
        type: entry.key,
        videoFileName: videoFileName,
      );

      if (path != null) {
        results[entry.key] = path;
      }
    }

    return results;
  }
}
