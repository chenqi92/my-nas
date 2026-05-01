import 'dart:io';

import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 通用 NAS 文件分享服务
///
/// 提供"流式下载远程文件到临时目录后调用系统分享面板"的统一实现。
/// 适用于所有"列表上下文菜单 → 分享"场景中文件类媒体（图书、漫画等）。
///
/// 与 [PhotoSaveService.sharePhotoFromStream] 分离的原因：
/// PhotoSaveService 内嵌了"照片专用"上下文（保存到相册、缩略图等），
/// 这里只关心通用文件分享。
class NasFileShareService {
  NasFileShareService._();

  /// 当前平台是否支持系统分享 API
  static bool get canShare =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows;

  /// 把 [fileSystem] 上 [path] 的文件流式下载到临时目录并触发系统分享。
  ///
  /// [fileName] 用作分享面板显示的标题以及临时文件名。
  /// [onProgress] 在已知文件大小时回调，参数 0~1。
  static Future<NasFileShareResult> shareFromStream({
    required NasFileSystem fileSystem,
    required String path,
    required String fileName,
    String? text,
    void Function(double progress)? onProgress,
  }) async {
    if (!canShare) {
      return const NasFileShareResult.failure('当前平台不支持系统分享');
    }

    File? tempFile;
    try {
      // 1. 探测文件大小（用于进度回调，非必须）
      int? totalSize;
      try {
        final info = await fileSystem.getFileInfo(path);
        totalSize = info.size;
      } on Exception catch (_) {
        // 部分协议拿不到大小，继续无进度即可
      }

      // 2. 流式写到临时目录
      final tempDir = await getTemporaryDirectory();
      tempFile = File(p.join(tempDir.path, 'share_$fileName'));

      final stream = await fileSystem.getFileStream(path);
      final sink = tempFile.openWrite();
      var received = 0;
      try {
        await for (final chunk in stream) {
          sink.add(chunk);
          received += chunk.length;
          if (totalSize != null && totalSize > 0) {
            onProgress?.call(received / totalSize);
          }
        }
      } finally {
        await sink.close();
      }

      if (!tempFile.existsSync()) {
        return const NasFileShareResult.failure('临时文件写入失败');
      }

      // 3. 调系统分享
      final result = await Share.shareXFiles(
        [XFile(tempFile.path, name: fileName)],
        text: text,
        subject: fileName,
      );

      // 4. 延迟清理临时文件——让系统分享面板有时间读完
      _scheduleCleanup(tempFile);

      return switch (result.status) {
        ShareResultStatus.success => const NasFileShareResult.success(),
        ShareResultStatus.dismissed => const NasFileShareResult.cancelled(),
        ShareResultStatus.unavailable =>
          const NasFileShareResult.failure('系统分享不可用'),
      };
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'NasFileShareService.shareFromStream 失败');
      if (tempFile != null) {
        _scheduleCleanup(tempFile);
      }
      return NasFileShareResult.failure(e.toString());
    }
  }

  static void _scheduleCleanup(File file) {
    Future<void>.delayed(const Duration(seconds: 30), () async {
      try {
        if (file.existsSync()) {
          await file.delete();
        }
      } on Exception catch (e, st) {
        AppError.ignore(e, st, 'NasFileShareService 清理临时文件失败');
      }
    });
    logger.d('NasFileShareService: 已安排 30s 后清理 ${file.path}');
  }
}

/// 分享结果
class NasFileShareResult {
  const NasFileShareResult._(this.status, [this.error]);

  const NasFileShareResult.success() : this._(NasFileShareStatus.success);
  const NasFileShareResult.cancelled() : this._(NasFileShareStatus.cancelled);
  const NasFileShareResult.failure(String message)
      : this._(NasFileShareStatus.failure, message);

  final NasFileShareStatus status;
  final String? error;

  bool get isSuccess => status == NasFileShareStatus.success;
  bool get isFailure => status == NasFileShareStatus.failure;
  bool get isCancelled => status == NasFileShareStatus.cancelled;
}

enum NasFileShareStatus { success, failure, cancelled }
