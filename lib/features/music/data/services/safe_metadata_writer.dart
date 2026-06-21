import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/music_metadata_writer.dart';
import 'package:my_nas/features/music/data/services/unified_metadata_writer.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 安全的元数据写入服务
///
/// 解决播放时写入的冲突问题：
/// 1. 检测文件是否正在播放
/// 2. 暂停播放并释放文件句柄
/// 3. 写入元数据
/// 4. 恢复播放（保持播放位置）
///
/// 场景分析：
/// - NAS 流式播放：无冲突，直接写入
/// - 本地缓存播放：需要暂停，写入缓存文件
/// - 本地文件播放：需要暂停，写入源文件
class SafeMetadataWriter {
  SafeMetadataWriter(this._ref);

  final Ref _ref;
  final _writer = UnifiedMetadataWriter();

  /// 获取当前播放状态
  MusicPlayerState get _playerState => _ref.read(musicPlayerControllerProvider);

  /// 获取播放器控制器
  MusicPlayerNotifier get _playerController =>
      _ref.read(musicPlayerControllerProvider.notifier);

  /// 安全写入本地文件元数据
  ///
  /// 自动检测并处理播放冲突
  Future<SafeWriteResult> writeToLocalFile(
    String filePath,
    WritableMetadata metadata,
  ) async {
    final currentMusic = _ref.read(currentMusicProvider);
    final isPlaying = _playerState.isPlaying;

    // 检查是否正在播放此文件
    final isPlayingThisFile = _isPlayingFile(currentMusic, filePath);

    if (isPlayingThisFile) {
      logger.i('SafeMetadataWriter: 检测到文件正在播放，将暂停后写入');
      return _writeWithPlaybackControl(filePath, metadata, isPlaying);
    }

    // 文件未在播放，直接写入
    final success = await _writer.writeMetadata(filePath, metadata);
    return SafeWriteResult(
      success: success,
      wasPlaying: false,
      error: success ? null : appL10n.musicMetadataWriteFailedSimple,
    );
  }

  /// 安全写入 NAS 文件元数据
  ///
  /// NAS 文件通常通过 HTTP 代理播放，不会有本地文件锁定问题
  /// 但如果文件被缓存到本地，仍需要处理
  Future<SafeWriteResult> writeToNasFile(
    NasFileSystem fileSystem,
    String remotePath,
    WritableMetadata metadata, {
    void Function(double progress, String stage)? onProgress,
  }) async {
    final currentMusic = _ref.read(currentMusicProvider);
    final playerState = _playerState;

    // 检查是否正在播放此 NAS 文件（通过路径匹配）
    final isPlayingThisFile = currentMusic?.path == remotePath;

    Duration? savedPosition;
    var wasPlaying = false;

    if (isPlayingThisFile && playerState.isPlaying) {
      logger.i('SafeMetadataWriter: 检测到 NAS 文件正在播放');
      wasPlaying = true;

      // 保存播放位置
      savedPosition = playerState.position;

      // 暂停播放
      await _playerController.pause();

      // 等待播放器释放资源
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    try {
      onProgress?.call(0.0, appL10n.musicMetadataProgressPreparing);

      final result = await _writer.writeToNasFile(
        fileSystem,
        remotePath,
        metadata,
        onProgress: onProgress,
      );

      if (!result.success) {
        return SafeWriteResult(
          success: false,
          wasPlaying: wasPlaying,
          error: result.error,
        );
      }

      // 恢复播放
      if (wasPlaying && savedPosition != null) {
        onProgress?.call(1.0, appL10n.musicMetadataProgressResuming);
        await _resumePlayback(savedPosition);
      }

      return SafeWriteResult(
        success: true,
        wasPlaying: wasPlaying,
        resumedAt: savedPosition,
      );
    } catch (e) {
      // 尝试恢复播放
      if (wasPlaying) {
        try {
          await _playerController.resume();
        } catch (re, rst) {
          AppError.ignore(re, rst, '写入失败后恢复播放失败');
        }
      }

      return SafeWriteResult(
        success: false,
        wasPlaying: wasPlaying,
        error: e.toString(),
      );
    }
  }

  /// 带播放控制的写入
  Future<SafeWriteResult> _writeWithPlaybackControl(
    String filePath,
    WritableMetadata metadata,
    bool wasPlaying,
  ) async {
    Duration? savedPosition;

    try {
      // 保存当前播放位置
      savedPosition = _playerState.position;

      // 暂停播放
      await _playerController.pause();

      // Windows 需要更长时间释放文件句柄
      if (Platform.isWindows) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }

      // 尝试写入
      final success = await _writer.writeMetadata(filePath, metadata);

      if (!success) {
        // 写入失败，恢复播放
        if (wasPlaying) {
          await _resumePlayback(savedPosition);
        }
        return SafeWriteResult(
          success: false,
          wasPlaying: wasPlaying,
          error: appL10n.musicMetadataWriteFailedFileInUse,
        );
      }

      // 写入成功，恢复播放
      if (wasPlaying) {
        await _resumePlayback(savedPosition);
      }

      return SafeWriteResult(
        success: true,
        wasPlaying: wasPlaying,
        resumedAt: savedPosition,
      );
    } catch (e) {
      // 尝试恢复播放
      if (wasPlaying) {
        try {
          await _playerController.resume();
        } catch (re, rst) {
          AppError.ignore(re, rst, '写入失败后恢复播放失败');
        }
      }

      return SafeWriteResult(
        success: false,
        wasPlaying: wasPlaying,
        error: e.toString(),
      );
    }
  }

  /// 恢复播放到指定位置
  Future<void> _resumePlayback(Duration? position) async {
    // 短暂延迟确保文件可以被重新打开
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // 先 seek 到保存的位置
    if (position != null) {
      await _playerController.seek(position);
    }

    // 恢复播放
    await _playerController.resume();
  }

  /// 检查是否正在播放指定文件
  bool _isPlayingFile(MusicItem? currentMusic, String filePath) {
    if (currentMusic == null) return false;

    // 检查 URL 是否匹配
    final url = currentMusic.url;
    if (url.startsWith('file://')) {
      final playingPath = Uri.parse(url).toFilePath();
      return _pathsEqual(playingPath, filePath);
    }

    // 检查路径是否匹配
    return _pathsEqual(currentMusic.path, filePath);
  }

  /// 路径比较（处理不同平台的路径分隔符）
  bool _pathsEqual(String path1, String path2) {
    // 统一路径分隔符
    final normalized1 = path1.replaceAll(r'\', '/').toLowerCase();
    final normalized2 = path2.replaceAll(r'\', '/').toLowerCase();
    return normalized1 == normalized2;
  }

  /// 批量写入（自动处理播放冲突）
  Future<List<SafeWriteResult>> batchWrite(
    List<BatchWriteItem> items, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final results = <SafeWriteResult>[];
    var needsPlaybackResume = false;
    Duration? savedPosition;

    // 检查是否有任何文件正在播放
    final currentMusic = _ref.read(currentMusicProvider);
    final playerState = _playerState;

    for (final item in items) {
      final isPlayingThis = item.isLocal
          ? _isPlayingFile(currentMusic, item.path)
          : currentMusic?.path == item.path;

      if (isPlayingThis && playerState.isPlaying) {
        needsPlaybackResume = true;
        savedPosition = playerState.position;
        await _playerController.pause();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        break; // 只需要暂停一次
      }
    }

    // 批量写入
    for (var i = 0; i < items.length; i++) {
      final item = items[i];

      SafeWriteResult result;
      if (item.isLocal) {
        final success = await _writer.writeMetadata(item.path, item.metadata);
        result = SafeWriteResult(success: success, wasPlaying: false);
      } else {
        final nasResult = await _writer.writeToNasFile(
          item.fileSystem!,
          item.path,
          item.metadata,
        );
        result = SafeWriteResult(
          success: nasResult.success,
          wasPlaying: false,
          error: nasResult.error,
        );
      }

      results.add(result);
      onProgress?.call(i + 1, items.length);
    }

    // 恢复播放
    if (needsPlaybackResume && savedPosition != null) {
      await _resumePlayback(savedPosition);
    }

    return results;
  }
}

/// 安全写入结果
class SafeWriteResult {
  const SafeWriteResult({
    required this.success,
    required this.wasPlaying,
    this.resumedAt,
    this.error,
  });

  final bool success;
  final bool wasPlaying;
  final Duration? resumedAt;
  final String? error;

  @override
  String toString() {
    if (success) {
      return wasPlaying
          ? 'SafeWriteResult(success, resumed at $resumedAt)'
          : 'SafeWriteResult(success)';
    }
    return 'SafeWriteResult(failed: $error)';
  }
}

/// 批量写入项
class BatchWriteItem {
  const BatchWriteItem.local({
    required this.path,
    required this.metadata,
  })  : isLocal = true,
        fileSystem = null;

  const BatchWriteItem.nas({
    required this.path,
    required this.metadata,
    required NasFileSystem this.fileSystem,
  }) : isLocal = false;

  final String path;
  final WritableMetadata metadata;
  final bool isLocal;
  final NasFileSystem? fileSystem;
}

/// Provider
final safeMetadataWriterProvider =
    Provider<SafeMetadataWriter>(SafeMetadataWriter.new);
