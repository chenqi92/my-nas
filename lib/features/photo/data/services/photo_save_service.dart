import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/file_name_sanitizer.dart';
import 'package:my_nas/core/utils/local_file_uri.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/core/utils/platform_capabilities.dart';
import 'package:my_nas/core/utils/tv_capabilities.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart' hide FileType;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 照片保存服务
/// 负责下载照片到本地/相册，以及分享功能
///
/// 支持多种数据源：
/// - HTTP/HTTPS URL（NAS API、群晖、QNAP等）
/// - 文件流（SMB、WebDAV等）
/// - 本地文件（file:// URL）
class PhotoSaveService {
  factory PhotoSaveService() => _instance ??= PhotoSaveService._();
  PhotoSaveService._();

  static PhotoSaveService? _instance;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 5),
    ),
  );

  /// 判断是否为桌面平台
  bool get isDesktop => PlatformCapabilities.isDesktop;

  /// 判断是否为移动平台
  bool get isMobile => PlatformCapabilities.isMobile;

  /// 是否支持保存到相册
  bool get canSaveToGallery => PlatformCapabilities.canSaveToGallery;

  /// 是否支持系统分享（TV 模式不支持）
  bool get canShare =>
      PlatformCapabilities.canShare && !TvCapabilities.isTvMode;

  /// 是否支持完整的系统分享（TV 模式不支持）
  bool get canShareNatively =>
      PlatformCapabilities.canShareNatively && !TvCapabilities.isTvMode;

  /// 下载照片（通过 HTTP URL）
  /// - 桌面端：弹出文件选择对话框，用户选择保存位置
  /// - 移动端：保存到相册
  /// - [cancelToken] 用于取消下载
  Future<SaveResult> downloadPhoto({
    required String url,
    required String fileName,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    File? tempFile;

    try {
      logger
        ..i('PhotoSaveService: 开始下载照片: $fileName, URL: $url')
        ..i(
          'PhotoSaveService: 平台信息 - isDesktop=$isDesktop, isMobile=$isMobile, canSaveToGallery=$canSaveToGallery',
        );

      // 1. 下载文件到临时目录
      // 远端文件名可能含 Windows 非法字符或超长，需清洗后再拼本地路径。
      tempFile = await _createUniqueTempFile('download', fileName);
      final tempPath = tempFile.path;
      logger.i('PhotoSaveService: 临时文件路径: $tempPath');

      final response = await _dio.download(
        url,
        tempPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress?.call(received / total);
          }
        },
      );

      logger.i('PhotoSaveService: 下载完成, HTTP状态码: ${response.statusCode}');

      if (response.statusCode != 200) {
        await _cleanupTempFile(tempFile);
        return SaveResult.failure(
          appL10n.photoSaveHttpStatusCodeError(response.statusCode ?? 0),
        );
      }

      final fileExists = await tempFile.exists();
      final fileSize = fileExists ? await tempFile.length() : 0;
      logger.i('PhotoSaveService: 临时文件检查 - 存在=$fileExists, 大小=$fileSize bytes');

      if (!fileExists) {
        await _cleanupTempFile(tempFile);
        return SaveResult.failure(appL10n.photoSaveDownloadedFileNotFound);
      }

      if (fileSize == 0) {
        await _cleanupTempFile(tempFile);
        return SaveResult.failure(appL10n.photoSaveDownloadedFileEmpty);
      }

      // 2. 根据平台保存文件
      logger.i('PhotoSaveService: 准备保存文件, 目标平台: ${isDesktop ? "桌面" : "移动"}');
      if (isDesktop) {
        return _saveToDesktop(tempFile, fileName);
      } else {
        return _saveToGallery(tempFile, fileName);
      }
    } on DioException catch (e, st) {
      // 清理临时文件
      await _cleanupTempFile(tempFile);

      if (e.type == DioExceptionType.cancel) {
        AppError.ignore(e, st, '用户取消照片下载');
        logger.i('PhotoSaveService: 下载已取消');
        return SaveResult.cancelled();
      }

      AppError.handle(e, st, 'PhotoSaveService.downloadPhoto', {'url': url});

      logger
        ..e('PhotoSaveService: 下载失败 (DioException)', e)
        ..e(
          'PhotoSaveService: DioException type=${e.type}, message=${e.message}',
        );
      return SaveResult.failure(
        '${appL10n.photoSaveDownloadFailed(appL10n.photoSaveResultFailed)}: ${_getDioErrorMessage(e)}',
      );
    } on Object catch (e, stackTrace) {
      // 清理临时文件
      await _cleanupTempFile(tempFile);

      AppError.handle(e, stackTrace, 'PhotoSaveService.downloadPhoto', {
        'url': url,
      });

      logger
        ..e('PhotoSaveService: 保存失败 (Exception)', e)
        ..e('PhotoSaveService: StackTrace: $stackTrace');
      return SaveResult.failure(appL10n.photoSaveFailed(e.toString()));
    }
  }

  /// 从文件系统流下载照片（用于 SMB、WebDAV 等非 HTTP 源）
  /// - 桌面端：弹出文件选择对话框，用户选择保存位置
  /// - 移动端：保存到相册
  Future<SaveResult> downloadPhotoFromStream({
    required NasFileSystem fileSystem,
    required String path,
    required String fileName,
    void Function(double progress)? onProgress,
  }) async {
    File? tempFile;

    try {
      logger
        ..i('PhotoSaveService: 开始从流下载照片: $fileName, path=$path')
        ..i('PhotoSaveService: 文件系统类型: ${fileSystem.runtimeType}');

      // 1. 获取文件信息（用于计算进度）
      int? totalSize;
      try {
        final fileInfo = await fileSystem.getFileInfo(path);
        totalSize = fileInfo.size;
        logger.i('PhotoSaveService: 文件大小: $totalSize bytes');
      } on Object catch (e, st) {
        AppError.ignore(e, st, '远端照片无法获取文件大小，继续使用无进度模式');
        logger.w('PhotoSaveService: 获取文件信息失败: $e');
        // 获取文件信息失败，继续下载但不显示进度
      }

      // 2. 获取文件流并写入临时文件
      tempFile = await _createUniqueTempFile('download', fileName);
      final tempPath = tempFile.path;
      logger
        ..i('PhotoSaveService: 临时文件路径: $tempPath')
        ..i('PhotoSaveService: 开始获取文件流...');
      final stream = await fileSystem.getFileStream(path);
      final sink = tempFile.openWrite();
      var receivedBytes = 0;

      try {
        await for (final chunk in stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalSize != null && totalSize > 0) {
            onProgress?.call(receivedBytes / totalSize);
          }
        }
      } finally {
        // Windows 上未关闭的 sink 会阻止 catch 分支删除临时文件。
        await sink.close();
      }
      logger.i('PhotoSaveService: 流式下载完成, 接收字节数: $receivedBytes');

      final fileExists = await tempFile.exists();
      final fileSize = fileExists ? await tempFile.length() : 0;
      logger.i('PhotoSaveService: 临时文件检查 - 存在=$fileExists, 大小=$fileSize bytes');

      if (!fileExists) {
        return SaveResult.failure(appL10n.photoSaveDownloadedFileNotFound);
      }

      if (fileSize == 0) {
        await _cleanupTempFile(tempFile);
        return SaveResult.failure(appL10n.photoSaveDownloadedFileEmpty);
      }

      // 3. 根据平台保存文件
      logger.i('PhotoSaveService: 准备保存文件, 目标平台: ${isDesktop ? "桌面" : "移动"}');
      if (isDesktop) {
        return _saveToDesktop(tempFile, fileName);
      } else {
        return _saveToGallery(tempFile, fileName);
      }
    } on Object catch (e, stackTrace) {
      // 清理临时文件
      await _cleanupTempFile(tempFile);

      AppError.handle(
        e,
        stackTrace,
        'PhotoSaveService.downloadPhotoFromStream',
        {'path': path},
      );

      logger
        ..e('PhotoSaveService: 从流下载失败', e)
        ..e('PhotoSaveService: StackTrace: $stackTrace');
      return SaveResult.failure(appL10n.photoSaveFailed(e.toString()));
    }
  }

  /// 从本地文件保存照片（用于本地文件系统）
  /// - 桌面端：弹出文件选择对话框，用户选择保存位置
  /// - 移动端：保存到相册
  Future<SaveResult> saveLocalPhoto({
    required String localPath,
    required String fileName,
  }) async {
    try {
      logger.i('PhotoSaveService: 开始保存本地照片: $fileName');

      final sourceFile = File(localPath);
      if (!await sourceFile.exists()) {
        return SaveResult.failure(appL10n.photoSaveSourceFileNotFound);
      }

      // 根据平台保存文件
      if (isDesktop) {
        return _saveToDesktop(sourceFile, fileName, deleteAfter: false);
      } else {
        return _saveToGallery(sourceFile, fileName, deleteAfter: false);
      }
    } on Object catch (e, st) {
      AppError.handle(e, st, 'PhotoSaveService.saveLocalPhoto', {
        'localPath': localPath,
      });
      logger.e('PhotoSaveService: 保存本地照片失败', e);
      return SaveResult.failure(appL10n.photoSaveFailed(e.toString()));
    }
  }

  /// 智能下载照片（根据 URL 类型自动选择下载方式）
  ///
  /// 支持的 URL 类型：
  /// - http:// 或 https:// - 使用 HTTP 下载
  /// - file:// - 直接保存本地文件
  /// - smb:// 或 webdav:// - 使用文件流下载
  Future<SaveResult> smartDownloadPhoto({
    required String url,
    required String path,
    required String fileName,
    NasFileSystem? fileSystem,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    logger.i('PhotoSaveService: 智能下载 url=$url, path=$path');

    // HTTP/HTTPS URL - 使用 Dio 下载
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return downloadPhoto(
        url: url,
        fileName: fileName,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    }

    // file:// URL - 直接保存本地文件
    if (url.startsWith('file://')) {
      final localPath = localPathFromFileUri(url);
      if (localPath == null) {
        // 调用方（photo_viewer_page）只判断返回的 SaveResult，不 catch 异常：
        // 抛出会跳过关闭进度对话框的代码，让用户卡在无提示的模态框上。
        logger.w('PhotoSaveService: 无法解析本地照片 file URI: $url');
        return SaveResult.failure(appL10n.photoSaveUnsupportedUrlType);
      }
      return saveLocalPhoto(localPath: localPath, fileName: fileName);
    }

    // SMB/WebDAV 等特殊协议 - 使用文件流
    if (fileSystem != null) {
      return downloadPhotoFromStream(
        fileSystem: fileSystem,
        path: path,
        fileName: fileName,
        onProgress: onProgress,
      );
    }

    return SaveResult.failure(appL10n.photoSaveUnsupportedUrlType);
  }

  /// 桌面端：弹出文件对话框让用户选择保存位置（TV 模式不支持）
  Future<SaveResult> _saveToDesktop(
    File sourceFile,
    String fileName, {
    bool deleteAfter = true,
  }) async {
    if (TvCapabilities.isTvMode) {
      if (deleteAfter) await _cleanupTempFile(sourceFile);
      return SaveResult.failure(appL10n.photoSavePlatformNotSupported);
    }

    try {
      // 弹出保存文件对话框
      final result = await FilePicker.platform.saveFile(
        dialogTitle: appL10n.photoSaveDialogTitle,
        fileName: fileName,
        type: FileType.image,
        allowedExtensions: _getAllowedExtensions(fileName),
      );

      if (result == null) {
        // 用户取消
        if (deleteAfter) await _cleanupTempFile(sourceFile);
        return SaveResult.cancelled();
      }

      // 复制文件到选定位置
      await sourceFile.copy(result);
      if (deleteAfter) await _cleanupTempFile(sourceFile);

      logger.i('PhotoSaveService: 照片已保存到: $result');
      return SaveResult.success(result);
    } on Object catch (e, st) {
      AppError.handle(e, st, 'PhotoSaveService.saveToDesktop');
      logger.e('PhotoSaveService: 桌面端保存失败', e);
      if (deleteAfter) await _cleanupTempFile(sourceFile);
      return SaveResult.failure(appL10n.photoSaveFailed(e.toString()));
    }
  }

  /// 移动端：保存到相册
  Future<SaveResult> _saveToGallery(
    File sourceFile,
    String fileName, {
    bool deleteAfter = true,
  }) async {
    var workingFile = sourceFile;
    var cleanupFile = deleteAfter ? sourceFile : null;
    try {
      // 检查源文件是否存在和大小
      final fileExists = await sourceFile.exists();
      final fileSize = fileExists ? await sourceFile.length() : 0;
      logger.i(
        'PhotoSaveService: 准备保存到相册, 文件存在=$fileExists, 大小=$fileSize bytes, 路径=${sourceFile.path}',
      );

      if (!fileExists) {
        await _cleanupTempFile(cleanupFile);
        return SaveResult.failure(appL10n.photoSaveTempFileNotFound);
      }

      if (fileSize == 0) {
        await _cleanupTempFile(cleanupFile);
        return SaveResult.failure(appL10n.photoSaveDownloadedFileEmpty);
      }

      // 本地文件属于用户，不能为了相册排序直接改写其 EXIF。先复制到任务独占
      // 的临时目录，再只修改副本；下载得到的临时文件则可原地处理。
      if (!deleteAfter) {
        workingFile = await _createUniqueTempFile('gallery', fileName);
        cleanupFile = workingFile;
        await sourceFile.copy(workingFile.path);
      }

      // 更新 EXIF 时间戳为当前时间，使照片在相册中按下载时间排序
      final processedFile = await _updateExifTimestamp(workingFile, fileName);

      // 使用 gal 库保存到相册
      logger.i('PhotoSaveService: 调用 Gal.putImage...');
      await Gal.putImage(processedFile.path, album: 'MyNAS');

      // 删除临时文件
      await _cleanupTempFile(cleanupFile);

      logger.i('PhotoSaveService: 照片已成功保存到相册');
      return SaveResult.success(null, isGallery: true);
    } on GalException catch (e, st) {
      AppError.handle(e, st, 'PhotoSaveService.saveToGallery');
      logger
        ..e('PhotoSaveService: 保存到相册失败 (GalException)', e)
        ..e(
          'PhotoSaveService: GalException type=${e.type}, platformException=${e.platformException}',
        );
      await _cleanupTempFile(cleanupFile);

      // 处理权限问题
      if (e.type == GalExceptionType.accessDenied) {
        return SaveResult.failure(appL10n.photoSaveGalleryPermissionDenied);
      }
      return SaveResult.failure(appL10n.photoSaveToGalleryFailed(e.type.name));
    } on Object catch (e, stackTrace) {
      AppError.handle(e, stackTrace, 'PhotoSaveService.saveToGallery');
      logger
        ..e('PhotoSaveService: 保存到相册失败 (Exception)', e)
        ..e('PhotoSaveService: StackTrace: $stackTrace');
      await _cleanupTempFile(cleanupFile);
      return SaveResult.failure(appL10n.photoSaveToGalleryFailed(e.toString()));
    }
  }

  /// 分享照片
  /// 使用系统分享功能，支持 AirDrop、短信、邮件、社交应用等
  /// - [cancelToken] 用于取消下载
  Future<ShareResult> sharePhoto({
    required String url,
    required String fileName,
    String? text,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (!canShare) {
      return ShareResult.failure(appL10n.photoSavePlatformNotSupported);
    }

    File? tempFile;

    try {
      logger.i('PhotoSaveService: 开始分享照片: $fileName');

      // 1. 下载文件到临时目录
      tempFile = await _createUniqueTempFile('share', fileName);
      final tempPath = tempFile.path;

      final response = await _dio.download(
        url,
        tempPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress?.call(received / total);
          }
        },
      );

      if (response.statusCode != 200) {
        _scheduleCleanup(tempFile);
        return ShareResult.failure(
          appL10n.photoSaveHttpStatusCodeError(response.statusCode ?? 0),
        );
      }

      if (!await tempFile.exists()) {
        _scheduleCleanup(tempFile);
        return ShareResult.failure(appL10n.photoSaveFileNotFound);
      }

      // 2. 使用系统分享
      final xFile = XFile(tempPath);
      final result = await Share.shareXFiles(
        [xFile],
        text: text,
        subject: fileName,
      );

      // 分享完成后删除临时文件
      // 延迟一点删除，确保分享系统已经读取完文件
      _scheduleCleanup(tempFile);

      logger.i('PhotoSaveService: 分享结果: ${result.status}');

      return switch (result.status) {
        ShareResultStatus.success => ShareResult.success(),
        ShareResultStatus.dismissed => ShareResult.cancelled(),
        ShareResultStatus.unavailable => ShareResult.failure(
          appL10n.photoSaveShareFeatureUnavailable,
        ),
      };
    } on DioException catch (e, st) {
      _scheduleCleanup(tempFile);

      if (e.type == DioExceptionType.cancel) {
        AppError.ignore(e, st, '用户取消分享照片前的下载');
        logger.i('PhotoSaveService: 分享下载已取消');
        return ShareResult.cancelled();
      }

      AppError.handle(e, st, 'PhotoSaveService.sharePhotoDownload', {
        'url': url,
      });

      logger.e('PhotoSaveService: 分享失败 - 下载错误', e);
      return ShareResult.failure(
        appL10n.photoShareDownloadFailed(_getDioErrorMessage(e)),
      );
    } on Object catch (e, st) {
      _scheduleCleanup(tempFile);

      AppError.handle(e, st, 'PhotoSaveService.sharePhoto');
      logger.e('PhotoSaveService: 分享失败', e);
      return ShareResult.failure(appL10n.photoShareFailed(e.toString()));
    }
  }

  /// 直接从内存分享照片（用于已加载的照片）
  Future<ShareResult> sharePhotoFromBytes({
    required Uint8List bytes,
    required String fileName,
    String? text,
  }) async {
    if (!canShare) {
      return ShareResult.failure(appL10n.photoSavePlatformNotSupported);
    }

    File? tempFile;

    try {
      // 保存到临时文件
      tempFile = await _createUniqueTempFile('share', fileName);
      final tempPath = tempFile.path;
      await tempFile.writeAsBytes(bytes);

      // 分享
      final xFile = XFile(tempPath);
      final result = await Share.shareXFiles(
        [xFile],
        text: text,
        subject: fileName,
      );

      // 延迟删除临时文件
      _scheduleCleanup(tempFile);

      return switch (result.status) {
        ShareResultStatus.success => ShareResult.success(),
        ShareResultStatus.dismissed => ShareResult.cancelled(),
        ShareResultStatus.unavailable => ShareResult.failure(
          appL10n.photoSaveShareFeatureUnavailable,
        ),
      };
    } on Object catch (e, st) {
      _scheduleCleanup(tempFile);

      AppError.handle(e, st, 'PhotoSaveService.sharePhotoFromBytes');
      logger.e('PhotoSaveService: 分享失败', e);
      return ShareResult.failure(appL10n.photoShareFailed(e.toString()));
    }
  }

  /// 从本地文件分享照片
  Future<ShareResult> shareLocalPhoto({
    required String localPath,
    required String fileName,
    String? text,
  }) async {
    if (!canShare) {
      return ShareResult.failure(appL10n.photoSavePlatformNotSupported);
    }

    try {
      final file = File(localPath);
      if (!await file.exists()) {
        return ShareResult.failure(appL10n.photoSaveFileNotFound);
      }

      // 直接分享本地文件，无需复制
      final xFile = XFile(localPath);
      final result = await Share.shareXFiles(
        [xFile],
        text: text,
        subject: fileName,
      );

      logger.i('PhotoSaveService: 本地文件分享结果: ${result.status}');

      return switch (result.status) {
        ShareResultStatus.success => ShareResult.success(),
        ShareResultStatus.dismissed => ShareResult.cancelled(),
        ShareResultStatus.unavailable => ShareResult.failure(
          appL10n.photoSaveShareFeatureUnavailable,
        ),
      };
    } on Object catch (e, st) {
      AppError.handle(e, st, 'PhotoSaveService.shareLocalPhoto', {
        'localPath': localPath,
      });
      logger.e('PhotoSaveService: 分享本地文件失败', e);
      return ShareResult.failure(appL10n.photoShareFailed(e.toString()));
    }
  }

  /// 从文件系统流分享照片（用于 SMB、WebDAV 等非 HTTP 源）
  Future<ShareResult> sharePhotoFromStream({
    required NasFileSystem fileSystem,
    required String path,
    required String fileName,
    String? text,
    void Function(double progress)? onProgress,
  }) async {
    if (!canShare) {
      return ShareResult.failure(appL10n.photoSavePlatformNotSupported);
    }

    File? tempFile;

    try {
      logger.i('PhotoSaveService: 开始从流准备分享: $fileName');

      // 1. 获取文件信息（用于计算进度）
      int? totalSize;
      try {
        final fileInfo = await fileSystem.getFileInfo(path);
        totalSize = fileInfo.size;
      } on Object catch (e, st) {
        // 获取文件信息失败，继续但不显示进度
        AppError.ignore(e, st, '分享远端照片时无法获取大小，继续使用无进度模式');
      }

      // 2. 获取文件流并写入临时文件
      tempFile = await _createUniqueTempFile('share', fileName);
      final tempPath = tempFile.path;

      final stream = await fileSystem.getFileStream(path);
      final sink = tempFile.openWrite();
      var receivedBytes = 0;

      try {
        await for (final chunk in stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalSize != null && totalSize > 0) {
            onProgress?.call(receivedBytes / totalSize);
          }
        }
      } finally {
        await sink.close();
      }

      if (!await tempFile.exists()) {
        _scheduleCleanup(tempFile);
        return ShareResult.failure(appL10n.photoSharePrepareFileFailed);
      }

      // 3. 分享
      final xFile = XFile(tempPath);
      final result = await Share.shareXFiles(
        [xFile],
        text: text,
        subject: fileName,
      );

      // 延迟删除临时文件
      _scheduleCleanup(tempFile);

      logger.i('PhotoSaveService: 流式分享结果: ${result.status}');

      return switch (result.status) {
        ShareResultStatus.success => ShareResult.success(),
        ShareResultStatus.dismissed => ShareResult.cancelled(),
        ShareResultStatus.unavailable => ShareResult.failure(
          appL10n.photoSaveShareFeatureUnavailable,
        ),
      };
    } on Object catch (e, st) {
      _scheduleCleanup(tempFile);

      AppError.handle(e, st, 'PhotoSaveService.sharePhotoFromStream', {
        'path': path,
      });
      logger.e('PhotoSaveService: 从流分享失败', e);
      return ShareResult.failure(appL10n.photoShareFailed(e.toString()));
    }
  }

  /// 智能分享照片（根据 URL 类型自动选择分享方式）
  ///
  /// 支持的 URL 类型：
  /// - http:// 或 https:// - 下载后分享
  /// - file:// - 直接分享本地文件
  /// - smb:// 或其他 - 使用文件流下载后分享
  Future<ShareResult> smartSharePhoto({
    required String url,
    required String path,
    required String fileName,
    NasFileSystem? fileSystem,
    String? text,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    logger.i('PhotoSaveService: 智能分享 url=$url, path=$path');

    // HTTP/HTTPS URL - 使用 Dio 下载后分享
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return sharePhoto(
        url: url,
        fileName: fileName,
        text: text,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    }

    // file:// URL - 直接分享本地文件
    if (url.startsWith('file://')) {
      final localPath = localPathFromFileUri(url);
      if (localPath == null) {
        // 同 smartDownloadPhoto：调用方不 catch，必须走返回值报错。
        logger.w('PhotoSaveService: 无法解析本地照片 file URI: $url');
        return ShareResult.failure(appL10n.photoSaveUnsupportedUrlType);
      }
      return shareLocalPhoto(
        localPath: localPath,
        fileName: fileName,
        text: text,
      );
    }

    // SMB/WebDAV 等特殊协议 - 使用文件流
    if (fileSystem != null) {
      return sharePhotoFromStream(
        fileSystem: fileSystem,
        path: path,
        fileName: fileName,
        text: text,
        onProgress: onProgress,
      );
    }

    return ShareResult.failure(appL10n.photoSaveUnsupportedUrlType);
  }

  /// 请求相册权限（iOS/Android）
  Future<bool> requestGalleryPermission() async {
    if (!canSaveToGallery) return false;

    final hasAccess = await Gal.hasAccess(toAlbum: true);
    if (hasAccess) return true;

    return Gal.requestAccess(toAlbum: true);
  }

  /// 获取允许的文件扩展名
  List<String>? _getAllowedExtensions(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    if (ext.isEmpty) return null;

    // 移除前导点
    final extWithoutDot = ext.substring(1);
    return [extWithoutDot];
  }

  /// 更新图片的 EXIF 时间戳为当前时间
  ///
  /// 这样保存到相册后，照片会按下载时间排序而不是原始拍摄时间
  /// 解决了从 NAS 下载的照片可能排列在相册很前面的问题
  Future<File> _updateExifTimestamp(File sourceFile, String fileName) async {
    try {
      final ext = p.extension(fileName).toLowerCase();

      // 只处理 JPEG 图片，其他格式（PNG、GIF等）通常不带 EXIF 或处理方式不同
      if (ext != '.jpg' && ext != '.jpeg') {
        logger.i('PhotoSaveService: 非 JPEG 格式，跳过 EXIF 时间戳更新');
        return sourceFile;
      }

      final bytes = await sourceFile.readAsBytes();
      final image = img.decodeJpg(bytes);

      if (image == null) {
        logger.w('PhotoSaveService: 无法解码 JPEG 图片，跳过 EXIF 时间戳更新');
        return sourceFile;
      }

      // 格式化当前时间为 EXIF 日期格式: "YYYY:MM:DD HH:MM:SS"
      final now = DateTime.now();
      final exifDateStr =
          '${now.year}:${now.month.toString().padLeft(2, '0')}:${now.day.toString().padLeft(2, '0')} '
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

      // 更新 EXIF 时间相关字段
      // DateTimeOriginal - 原始拍摄时间
      // DateTimeDigitized - 数字化时间
      // DateTime - 文件修改时间
      image.exif.exifIfd['DateTimeOriginal'] = exifDateStr;
      image.exif.exifIfd['DateTimeDigitized'] = exifDateStr;
      image.exif.imageIfd['DateTime'] = exifDateStr;

      // 重新编码并保存
      final updatedBytes = img.encodeJpg(image, quality: 95);
      await sourceFile.writeAsBytes(updatedBytes);

      logger.i('PhotoSaveService: EXIF 时间戳已更新为 $exifDateStr');
      return sourceFile;
    } on Object catch (e, st) {
      // 如果更新失败，仍然使用原文件
      AppError.ignore(e, st, '更新照片 EXIF 时间失败，保留原始文件继续保存');
      logger.w('PhotoSaveService: 更新 EXIF 时间戳失败: $e，使用原文件');
      return sourceFile;
    }
  }

  /// 清理临时文件
  Future<void> _cleanupTempFile(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) {
        await file.delete();
      }
      final parent = file.parent;
      if (p.basename(parent.path).startsWith('mynas_photo_') &&
          await parent.exists()) {
        await parent.delete();
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '清理临时照片文件失败');
    }
  }

  /// 延迟清理临时文件
  void _scheduleCleanup(File? file) {
    if (file == null) return;
    AppError.fireAndForget(
      Future<void>.delayed(
        const Duration(minutes: 5),
      ).then((_) => _cleanupTempFile(file)),
      action: 'photoSave.cleanupTemporaryShareFile',
    );
  }

  Future<File> _createUniqueTempFile(String purpose, String fileName) async {
    final root = await getTemporaryDirectory();
    final work = await root.createTemp('mynas_photo_${purpose}_');
    return File(p.join(work.path, sanitizeFileName(fileName)));
  }

  /// 获取 Dio 错误消息
  String _getDioErrorMessage(DioException e) => switch (e.type) {
    DioExceptionType.connectionTimeout =>
      appL10n.photoDioErrorConnectionTimeout,
    DioExceptionType.sendTimeout => appL10n.photoDioErrorSendTimeout,
    DioExceptionType.receiveTimeout => appL10n.photoDioErrorReceiveTimeout,
    DioExceptionType.badResponse => appL10n.photoDioErrorBadResponse(
      e.response?.statusCode ?? 0,
    ),
    DioExceptionType.cancel => appL10n.photoDioErrorCancelled,
    DioExceptionType.connectionError => appL10n.photoDioErrorConnectionFailed,
    DioExceptionType.unknown => e.message ?? appL10n.photoDioErrorUnknown,
    _ => e.message ?? appL10n.photoDioErrorNetwork,
  };
}

/// 保存结果
class SaveResult {
  const SaveResult._({
    required this.status,
    this.path,
    this.error,
    this.isGallery = false,
  });

  factory SaveResult.success(String? path, {bool isGallery = false}) =>
      SaveResult._(
        status: SaveStatus.success,
        path: path,
        isGallery: isGallery,
      );

  factory SaveResult.failure(String error) =>
      SaveResult._(status: SaveStatus.failure, error: error);

  factory SaveResult.cancelled() =>
      const SaveResult._(status: SaveStatus.cancelled);

  final SaveStatus status;
  final String? path;
  final String? error;
  final bool isGallery;

  bool get isSuccess => status == SaveStatus.success;
  bool get isCancelled => status == SaveStatus.cancelled;
  bool get isFailure => status == SaveStatus.failure;

  String get message => switch (status) {
    SaveStatus.success when isGallery => appL10n.photoSaveResultSavedToGallery,
    SaveStatus.success => appL10n.photoSaveResultSavedTo(path ?? ''),
    SaveStatus.cancelled => appL10n.photoSaveResultCancelled,
    SaveStatus.failure => error ?? appL10n.photoSaveResultFailed,
  };
}

enum SaveStatus { success, failure, cancelled }

/// 分享结果
class ShareResult {
  const ShareResult._({required this.status, this.error});

  factory ShareResult.success() =>
      const ShareResult._(status: ShareStatus.success);

  factory ShareResult.failure(String error) =>
      ShareResult._(status: ShareStatus.failure, error: error);

  factory ShareResult.cancelled() =>
      const ShareResult._(status: ShareStatus.cancelled);

  final ShareStatus status;
  final String? error;

  bool get isSuccess => status == ShareStatus.success;
  bool get isCancelled => status == ShareStatus.cancelled;
  bool get isFailure => status == ShareStatus.failure;
}

enum ShareStatus { success, failure, cancelled }
