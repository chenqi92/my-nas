import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/core/utils/nas_path.dart';
import 'package:my_nas/features/music/data/services/audiotags_metadata_writer.dart';
import 'package:my_nas/features/music/data/services/ffmpeg_metadata_writer.dart';
import 'package:my_nas/features/music/data/services/metadata_write_lock.dart';
import 'package:my_nas/features/music/data/services/music_metadata_writer.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 统一的音乐元数据写入服务
///
/// 自动选择最合适的写入器：
/// 1. audiotags (lofty-rs) - 主方案，支持大多数格式
/// 2. FFmpeg/Tone - 备选方案，用于 DSD/WMA 等特殊格式
///
/// 支持的操作：
/// - 写入本地文件元数据
/// - 写入 NAS 文件元数据（下载 -> 修改 -> 上传）
/// - 批量写入
///
/// 大文件处理策略：
/// - < 50MB: 直接在内存中处理
/// - 50MB - 200MB: 使用流式下载，分块处理
/// - > 200MB: 警告用户，可能需要较长时间
class UnifiedMetadataWriter implements MusicMetadataWriter {
  factory UnifiedMetadataWriter() => _instance;
  UnifiedMetadataWriter._();

  static final UnifiedMetadataWriter _instance = UnifiedMetadataWriter._();

  final _audiotagsWriter = AudiotagsMetadataWriter();
  final _ffmpegWriter = FFmpegMetadataWriter();

  late Directory _tempDir;
  bool _initialized = false;

  /// 超大文件阈值（超过此值会警告用户）
  static const _veryLargeFileThreshold = 200 * 1024 * 1024; // 200MB

  /// 初始化
  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _tempDir = await getTemporaryDirectory();
    _initialized = true;
  }

  @override
  List<String> get supportedFormats {
    final formats = <String>{}
      ..addAll(_audiotagsWriter.supportedFormats)
      ..addAll(_ffmpegWriter.supportedFormats);
    return formats.toList()..sort();
  }

  @override
  bool isFormatSupported(String extension) =>
      _audiotagsWriter.isFormatSupported(extension) ||
      _ffmpegWriter.isFormatSupported(extension);

  /// 获取格式使用的写入器名称
  String getWriterName(String extension) {
    if (_audiotagsWriter.isFormatSupported(extension) &&
        !_audiotagsWriter.needsFallback(extension)) {
      return 'audiotags';
    }
    return 'ffmpeg';
  }

  @override
  Future<bool> writeMetadata(String filePath, WritableMetadata metadata) async {
    await _ensureInitialized();

    // 使用文件锁防止并发写入
    return metadataWriteLock.withLock(filePath, () async {
      final ext = p.extension(filePath).toLowerCase();

      // 优先使用 audiotags（性能更好）
      if (_audiotagsWriter.isFormatSupported(ext) &&
          !_audiotagsWriter.needsFallback(ext)) {
        final result = await _audiotagsWriter.writeMetadata(filePath, metadata);
        if (result) return true;
        // 失败则尝试备选方案
        logger.d('UnifiedMetadataWriter: audiotags 失败，尝试 FFmpeg');
      }

      // 使用 FFmpeg 作为备选
      return _ffmpegWriter.writeMetadata(filePath, metadata);
    });
  }

  @override
  Future<bool> writeCover(
    String filePath,
    Uint8List coverData, {
    String mimeType = 'image/jpeg',
  }) async {
    await _ensureInitialized();

    // 使用文件锁防止并发写入
    return metadataWriteLock.withLock(filePath, () async {
      final ext = p.extension(filePath).toLowerCase();

      if (_audiotagsWriter.isFormatSupported(ext) &&
          !_audiotagsWriter.needsFallback(ext)) {
        final result = await _audiotagsWriter.writeCover(
          filePath,
          coverData,
          mimeType: mimeType,
        );
        if (result) return true;
      }

      return _ffmpegWriter.writeCover(filePath, coverData, mimeType: mimeType);
    });
  }

  @override
  Future<bool> removeAllMetadata(String filePath) async {
    await _ensureInitialized();

    // 使用文件锁防止并发写入
    return metadataWriteLock.withLock(filePath, () async {
      final ext = p.extension(filePath).toLowerCase();

      if (_audiotagsWriter.isFormatSupported(ext) &&
          !_audiotagsWriter.needsFallback(ext)) {
        final result = await _audiotagsWriter.removeAllMetadata(filePath);
        if (result) return true;
      }

      return _ffmpegWriter.removeAllMetadata(filePath);
    });
  }

  /// 读取元数据
  Future<WritableMetadata?> readMetadata(String filePath) async {
    await _ensureInitialized();

    final ext = p.extension(filePath).toLowerCase();

    if (_audiotagsWriter.isFormatSupported(ext)) {
      return _audiotagsWriter.readMetadata(filePath);
    }

    // FFmpeg 读取需要另外实现
    return null;
  }

  /// 写入 NAS 文件的元数据
  ///
  /// 流程：
  /// 1. 下载文件到本地临时目录
  /// 2. 修改元数据
  /// 3. 上传回 NAS
  /// 4. 清理临时文件
  ///
  /// [fileSystem] NAS 文件系统
  /// [remotePath] NAS 上的文件路径
  /// [metadata] 要写入的元数据
  /// [onProgress] 进度回调 (0.0 - 1.0)
  Future<NasMetadataWriteResult> writeToNasFile(
    NasFileSystem fileSystem,
    String remotePath,
    WritableMetadata metadata, {
    void Function(double progress, String stage)? onProgress,
  }) async {
    await _ensureInitialized();

    final ext = nasPathExtension(remotePath).toLowerCase();

    if (!isFormatSupported(ext)) {
      return NasMetadataWriteResult(
        success: false,
        error: appL10n.musicWriterUnsupportedFormat(ext),
      );
    }

    File? tempFile;

    try {
      // 获取文件信息
      onProgress?.call(0.0, appL10n.musicWriterStageGetFileInfo);
      final fileInfo = await fileSystem.getFileInfo(remotePath);
      final fileSize = fileInfo.size;

      // 大文件警告
      if (fileSize > _veryLargeFileThreshold) {
        logger.w('UnifiedMetadataWriter: 超大文件 (${fileSize ~/ 1024 ~/ 1024}MB)，处理可能需要较长时间');
      }

      // 创建临时文件
      final uniqueId = DateTime.now().millisecondsSinceEpoch;
      tempFile = File(p.join(_tempDir.path, 'metadata_edit_$uniqueId$ext'));

      // 下载文件
      onProgress?.call(0.1, appL10n.musicWriterStageDownloadFile);
      await _downloadFile(fileSystem, remotePath, tempFile, fileSize, (progress) {
        onProgress?.call(0.1 + progress * 0.4, appL10n.musicWriterStageDownloadFile);
      });

      // 写入元数据
      onProgress?.call(0.5, appL10n.musicWriterStageWriteMetadata);
      final writeResult = await writeMetadata(tempFile.path, metadata);

      if (!writeResult) {
        return NasMetadataWriteResult(
          success: false,
          error: appL10n.musicWriterWriteMetadataFailed,
        );
      }

      // 上传文件
      onProgress?.call(0.6, appL10n.musicWriterStageUploadFile);
      await _uploadFile(fileSystem, tempFile, remotePath, (progress) {
        onProgress?.call(0.6 + progress * 0.35, appL10n.musicWriterStageUploadFile);
      });

      onProgress?.call(1.0, appL10n.musicWriterStageComplete);

      return NasMetadataWriteResult(
        success: true,
        writerUsed: getWriterName(ext),
      );
    } catch (e, st) {
      logger.e('UnifiedMetadataWriter: NAS 文件写入失败', e, st);
      return NasMetadataWriteResult(
        success: false,
        error: e.toString(),
      );
    } finally {
      // 清理临时文件
      if (tempFile != null) {
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (e, st) {
          AppError.ignore(e, st, '清理 NAS 写入临时文件失败');
        }
      }
    }
  }

  /// 批量写入 NAS 文件元数据
  Future<List<NasMetadataWriteResult>> batchWriteToNasFiles(
    NasFileSystem fileSystem,
    List<NasBatchWriteItem> items, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final results = <NasMetadataWriteResult>[];

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final result = await writeToNasFile(
        fileSystem,
        item.remotePath,
        item.metadata,
      );
      results.add(result);
      onProgress?.call(i + 1, items.length);
    }

    return results;
  }

  /// 下载文件到本地
  ///
  /// [totalBytes] 文件总大小（避免重复调用 getFileInfo）
  Future<void> _downloadFile(
    NasFileSystem fileSystem,
    String remotePath,
    File localFile,
    int totalBytes,
    void Function(double progress) onProgress,
  ) async {
    final sink = localFile.openWrite();

    try {
      final stream = await fileSystem.getFileStream(remotePath);
      var downloadedBytes = 0;

      await for (final chunk in stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        if (totalBytes > 0) {
          onProgress(downloadedBytes / totalBytes);
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
  }

  /// 上传文件到 NAS
  ///
  /// 使用 NasFileSystem.upload 方法，支持流式上传，避免大文件内存问题
  Future<void> _uploadFile(
    NasFileSystem fileSystem,
    File localFile,
    String remotePath,
    void Function(double progress) onProgress,
  ) async {
    // 远端路径用 / 分隔，不能用 p.dirname/p.basename（Windows 宿主上会混入 \）
    final directory = nasPathDirname(remotePath);
    final fileName = nasPathBasename(remotePath);

    onProgress(0.0);

    await fileSystem.upload(
      localFile.path,
      directory,
      fileName: fileName,
      onProgress: (sent, total) {
        if (total > 0) {
          onProgress(sent / total);
        }
      },
    );

    onProgress(1.0);
  }

  /// 获取写入器状态
  Future<Map<String, dynamic>> getStatus() async {
    await _ensureInitialized();

    final ffmpegStatus = await _ffmpegWriter.getToolStatus();

    return {
      'audiotags': {
        'available': true,
        'formats': _audiotagsWriter.supportedFormats,
      },
      'ffmpeg': ffmpegStatus,
      'allSupportedFormats': supportedFormats,
    };
  }
}

/// NAS 文件元数据写入结果
class NasMetadataWriteResult {
  const NasMetadataWriteResult({
    required this.success,
    this.error,
    this.writerUsed,
  });

  final bool success;
  final String? error;
  final String? writerUsed;

  @override
  String toString() => success
      ? 'NasMetadataWriteResult(success, writer: $writerUsed)'
      : 'NasMetadataWriteResult(failed: $error)';
}

/// NAS 批量写入项
class NasBatchWriteItem {
  const NasBatchWriteItem({
    required this.remotePath,
    required this.metadata,
  });

  final String remotePath;
  final WritableMetadata metadata;
}
