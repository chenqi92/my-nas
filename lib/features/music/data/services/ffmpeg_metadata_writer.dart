import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/music_metadata_writer.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 基于 FFmpeg 的元数据写入实现
///
/// 用于处理 audiotags 不支持的格式：
/// - DSF/DFF (DSD 音频)
/// - WMA/ASF
/// - 其他特殊格式
///
/// 平台支持：
/// - Android/iOS/macOS: 使用 ffmpeg_kit_flutter_audio
/// - Windows/Linux: 使用系统 FFmpeg 或 Tone CLI
///
/// 注意：
/// - FFmpeg 写入元数据时需要重新编码或复制流
/// - 对于大文件可能需要较长时间
/// - 某些格式（如 DFF）不支持元数据
class FFmpegMetadataWriter implements MusicMetadataWriter {
  factory FFmpegMetadataWriter() => _instance;
  FFmpegMetadataWriter._();

  static final FFmpegMetadataWriter _instance = FFmpegMetadataWriter._();

  /// FFmpeg 支持的格式
  static const _supportedExtensions = {
    // DSD 格式
    '.dsf',
    '.dff',
    '.dsd',
    // Windows Media
    '.wma',
    '.asf',
    // 其他
    '.aac', // 纯 ADTS
    // 以及 audiotags 支持的所有格式（作为备选）
    '.mp3',
    '.flac',
    '.m4a',
    '.mp4',
    '.ogg',
    '.opus',
    '.wav',
    '.aiff',
    '.ape',
  };

  /// 不支持写入元数据的格式
  static const _metadataUnsupportedFormats = {
    '.dff', // DFF 格式不支持元数据
  };

  bool _ffmpegAvailable = false;
  bool _ffmpegKitAvailable = false;
  bool _toneAvailable = false;
  String? _tonePath;
  bool _initialized = false;

  @override
  List<String> get supportedFormats => _supportedExtensions.toList();

  @override
  bool isFormatSupported(String extension) {
    final ext = extension.toLowerCase();
    final normalized = ext.startsWith('.') ? ext : '.$ext';
    return _supportedExtensions.contains(normalized);
  }

  /// 初始化，检查可用的工具
  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    // 检查 FFmpeg 是否可用（桌面平台）
    if (Platform.isWindows || Platform.isLinux) {
      _ffmpegAvailable = await _checkFFmpegAvailable();
      logger.d('FFmpegMetadataWriter: FFmpeg 可用: $_ffmpegAvailable');
    }

    // 检查 FFmpegKit 是否可用（移动平台 + macOS）
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      _ffmpegKitAvailable = await _checkFFmpegKitAvailable();
      logger.d('FFmpegMetadataWriter: FFmpegKit 可用: $_ffmpegKitAvailable');
    }

    // 检查 Tone CLI 是否可用（桌面平台备选）
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      _tonePath = await _findTonePath();
      _toneAvailable = _tonePath != null;
      logger.d('FFmpegMetadataWriter: Tone 可用: $_toneAvailable ($_tonePath)');
    }

    _initialized = true;
  }

  /// 检查系统 FFmpeg 是否可用
  Future<bool> _checkFFmpegAvailable() async {
    try {
      final result = await Process.run('ffmpeg', ['-version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// 检查 FFmpegKit 是否可用
  Future<bool> _checkFFmpegKitAvailable() async {
    try {
      final session = await FFmpegKit.execute('-version');
      final returnCode = await session.getReturnCode();
      return ReturnCode.isSuccess(returnCode);
    } catch (e) {
      logger.d('FFmpegMetadataWriter: FFmpegKit 检查失败: $e');
      return false;
    }
  }

  /// 查找 Tone CLI 路径
  Future<String?> _findTonePath() async {
    // 检查系统 PATH
    try {
      final result = await Process.run(Platform.isWindows ? 'where' : 'which', [
        'tone',
      ]);
      if (result.exitCode == 0) {
        return 'tone';
      }
    } catch (e, st) {
      AppError.ignore(e, st, '系统 PATH 中未发现 tone 命令');
    }

    // 检查应用目录
    try {
      final appDir = await getApplicationSupportDirectory();
      final tonePath = p.join(
        appDir.path,
        'bin',
        Platform.isWindows ? 'tone.exe' : 'tone',
      );
      if (await File(tonePath).exists()) {
        return tonePath;
      }
    } catch (e, st) {
      AppError.ignore(e, st, '应用目录下未发现 tone 二进制');
    }

    return null;
  }

  @override
  Future<bool> writeMetadata(String filePath, WritableMetadata metadata) async {
    await _ensureInitialized();

    final ext = p.extension(filePath).toLowerCase();

    // 检查格式是否支持元数据
    if (_metadataUnsupportedFormats.contains(ext)) {
      logger.w('FFmpegMetadataWriter: 格式 $ext 不支持元数据');
      return false;
    }

    if (!isFormatSupported(ext)) {
      logger.w('FFmpegMetadataWriter: 不支持的格式: $ext');
      return false;
    }

    // 优先使用 Tone（更简单，支持更好）
    if (_toneAvailable) {
      return _writeWithTone(filePath, metadata);
    }

    // 使用系统 FFmpeg（桌面平台）
    if (_ffmpegAvailable) {
      return _writeWithFFmpeg(filePath, metadata);
    }

    // 使用 FFmpegKit（移动平台 + macOS）
    if (_ffmpegKitAvailable) {
      return _writeWithFFmpegKit(filePath, metadata);
    }

    logger.e('FFmpegMetadataWriter: 没有可用的写入工具');
    return false;
  }

  /// 使用 Tone CLI 写入
  Future<bool> _writeWithTone(
    String filePath,
    WritableMetadata metadata,
  ) async {
    File? coverFile;
    try {
      final args = <String>['tag', filePath];

      if (metadata.title != null) {
        args.addAll(['--meta-title', metadata.title!]);
      }
      if (metadata.artist != null) {
        args.addAll(['--meta-artist', metadata.artist!]);
      }
      if (metadata.album != null) {
        args.addAll(['--meta-album', metadata.album!]);
      }
      if (metadata.albumArtist != null) {
        args.addAll(['--meta-album-artist', metadata.albumArtist!]);
      }
      if (metadata.year != null) {
        args.addAll(['--meta-recording-date', metadata.year.toString()]);
      }
      if (metadata.trackNumber != null) {
        var trackStr = metadata.trackNumber.toString();
        if (metadata.totalTracks != null) {
          trackStr += '/${metadata.totalTracks}';
        }
        args.addAll(['--meta-track', trackStr]);
      }
      if (metadata.genre != null) {
        args.addAll(['--meta-genre', metadata.genre!]);
      }

      // 处理封面
      if (metadata.coverData != null && metadata.coverData!.isNotEmpty) {
        coverFile = await _saveTempCover(
          metadata.coverData!,
          metadata.coverMimeType,
        );
        if (coverFile != null) {
          args.addAll(['--cover', coverFile.path]);
        }
      }

      final result = await Process.run(_tonePath!, args);

      if (result.exitCode == 0) {
        logger.i('FFmpegMetadataWriter: Tone 写入成功: $filePath');
        return true;
      } else {
        logger.e('FFmpegMetadataWriter: Tone 写入失败: ${result.stderr}');
        return false;
      }
    } catch (e, st) {
      logger.e('FFmpegMetadataWriter: Tone 写入异常', e, st);
      return false;
    } finally {
      // 清理临时封面文件
      if (coverFile != null) {
        try {
          await coverFile.delete();
        } catch (e, st) {
          AppError.ignore(e, st, '清理 Tone 临时封面失败');
        }
      }
    }
  }

  /// 使用系统 FFmpeg 写入
  Future<bool> _writeWithFFmpeg(
    String filePath,
    WritableMetadata metadata,
  ) async {
    try {
      final ext = p.extension(filePath);
      final tempOutput = '${filePath}_temp$ext';

      final args = <String>[
        '-y', // 覆盖输出
        '-i', filePath,
      ];

      // 添加封面（如果有）
      File? coverFile;
      if (metadata.coverData != null && metadata.coverData!.isNotEmpty) {
        coverFile = await _saveTempCover(
          metadata.coverData!,
          metadata.coverMimeType,
        );
        if (coverFile != null) {
          args.addAll(['-i', coverFile.path]);
        }
      }

      // 复制流，不重新编码
      args.addAll(['-c', 'copy']);

      // 添加元数据
      if (metadata.title != null) {
        args.addAll(['-metadata', 'title=${metadata.title}']);
      }
      if (metadata.artist != null) {
        args.addAll(['-metadata', 'artist=${metadata.artist}']);
      }
      if (metadata.album != null) {
        args.addAll(['-metadata', 'album=${metadata.album}']);
      }
      if (metadata.albumArtist != null) {
        args.addAll(['-metadata', 'album_artist=${metadata.albumArtist}']);
      }
      if (metadata.year != null) {
        args.addAll(['-metadata', 'date=${metadata.year}']);
      }
      if (metadata.trackNumber != null) {
        args.addAll(['-metadata', 'track=${metadata.trackNumber}']);
      }
      if (metadata.genre != null) {
        args.addAll(['-metadata', 'genre=${metadata.genre}']);
      }

      // 如果有封面，映射封面流
      if (coverFile != null) {
        args.addAll([
          '-map', '0:a', // 音频流
          '-map', '1:v', // 封面图片
          '-metadata:s:v', 'title=Cover',
          '-metadata:s:v', 'comment=Cover (front)',
        ]);
      }

      args.add(tempOutput);

      final result = await Process.run('ffmpeg', args);

      // 清理临时封面
      if (coverFile != null) {
        try {
          await coverFile.delete();
        } catch (e, st) {
          AppError.ignore(e, st, '清理 FFmpeg 临时封面失败');
        }
      }

      if (result.exitCode == 0) {
        // 替换原文件
        await File(tempOutput).rename(filePath);
        logger.i('FFmpegMetadataWriter: FFmpeg 写入成功: $filePath');
        return true;
      } else {
        // 清理临时输出
        try {
          await File(tempOutput).delete();
        } catch (e, st) {
          AppError.ignore(e, st, 'FFmpeg 失败后清理临时文件失败');
        }
        logger.e('FFmpegMetadataWriter: FFmpeg 写入失败: ${result.stderr}');
        return false;
      }
    } catch (e, st) {
      logger.e('FFmpegMetadataWriter: FFmpeg 写入异常', e, st);
      return false;
    }
  }

  /// 使用 FFmpegKit 写入（移动平台）
  Future<bool> _writeWithFFmpegKit(
    String filePath,
    WritableMetadata metadata,
  ) async {
    File? coverFile;
    String? tempOutput;

    try {
      final ext = p.extension(filePath);
      tempOutput = '${filePath}_temp$ext';

      final args = <String>[
        '-y', // 覆盖输出
        '-i', _escapeFFmpegPath(filePath),
      ];

      // 添加封面（如果有）
      if (metadata.coverData != null && metadata.coverData!.isNotEmpty) {
        coverFile = await _saveTempCover(
          metadata.coverData!,
          metadata.coverMimeType,
        );
        if (coverFile != null) {
          args.addAll(['-i', _escapeFFmpegPath(coverFile.path)]);
        }
      }

      // 复制流，不重新编码
      args.addAll(['-c', 'copy']);

      // 添加元数据
      if (metadata.title != null) {
        args.addAll([
          '-metadata',
          'title=${_escapeMetadataValue(metadata.title!)}',
        ]);
      }
      if (metadata.artist != null) {
        args.addAll([
          '-metadata',
          'artist=${_escapeMetadataValue(metadata.artist!)}',
        ]);
      }
      if (metadata.album != null) {
        args.addAll([
          '-metadata',
          'album=${_escapeMetadataValue(metadata.album!)}',
        ]);
      }
      if (metadata.albumArtist != null) {
        args.addAll([
          '-metadata',
          'album_artist=${_escapeMetadataValue(metadata.albumArtist!)}',
        ]);
      }
      if (metadata.year != null) {
        args.addAll(['-metadata', 'date=${metadata.year}']);
      }
      if (metadata.trackNumber != null) {
        args.addAll(['-metadata', 'track=${metadata.trackNumber}']);
      }
      if (metadata.genre != null) {
        args.addAll([
          '-metadata',
          'genre=${_escapeMetadataValue(metadata.genre!)}',
        ]);
      }

      // 如果有封面，映射封面流
      if (coverFile != null) {
        args.addAll([
          '-map', '0:a', // 音频流
          '-map', '1:v', // 封面图片
          '-metadata:s:v', 'title=Cover',
          '-metadata:s:v', 'comment=Cover (front)',
        ]);
      }

      args.add(_escapeFFmpegPath(tempOutput));

      // 构建命令字符串
      final command = args.join(' ');
      logger.d('FFmpegMetadataWriter: 执行 FFmpegKit 命令: $command');

      // 执行 FFmpegKit 命令
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        // 替换原文件
        await File(tempOutput).rename(filePath);
        logger.i('FFmpegMetadataWriter: FFmpegKit 写入成功: $filePath');
        return true;
      } else {
        // 获取错误日志
        final logs = await session.getAllLogsAsString();
        logger.e('FFmpegMetadataWriter: FFmpegKit 写入失败: $logs');

        // 清理临时输出
        try {
          await File(tempOutput).delete();
        } catch (e, st) {
          AppError.ignore(e, st, 'FFmpegKit 失败后清理临时输出失败');
        }
        return false;
      }
    } catch (e, st) {
      logger.e('FFmpegMetadataWriter: FFmpegKit 写入异常', e, st);

      // 清理临时输出
      if (tempOutput != null) {
        try {
          await File(tempOutput).delete();
        } catch (ce, cst) {
          AppError.ignore(ce, cst, 'FFmpegKit 异常后清理临时输出失败');
        }
      }
      return false;
    } finally {
      // 清理临时封面
      if (coverFile != null) {
        try {
          await coverFile.delete();
        } catch (e, st) {
          AppError.ignore(e, st, '清理 FFmpegKit 临时封面失败');
        }
      }
    }
  }

  /// 转义 FFmpeg 路径（处理空格和特殊字符）
  String _escapeFFmpegPath(String path) {
    // FFmpegKit 在移动端需要对路径中的特殊字符进行处理
    if (path.contains(' ') || path.contains("'")) {
      // 使用单引号包裹，并转义内部的单引号
      return "'${path.replaceAll("'", r"'\''")}'"; //  ignore: use_raw_strings
    }
    return path;
  }

  /// 转义元数据值（处理特殊字符）
  String _escapeMetadataValue(String value) =>
      // ignore: use_raw_strings
      value
          .replaceAll(r'\', r'\\')
          .replaceAll('"', r'\"')
          .replaceAll("'", r"\'");

  /// 保存临时封面文件
  Future<File?> _saveTempCover(Uint8List data, String mimeType) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final ext = mimeType.contains('png') ? '.png' : '.jpg';
      final coverFile = File(
        p.join(tempDir.path, 'temp_cover_${const Uuid().v4()}$ext'),
      );
      await coverFile.writeAsBytes(data);
      return coverFile;
    } catch (e) {
      logger.e('FFmpegMetadataWriter: 保存临时封面失败', e);
      return null;
    }
  }

  @override
  Future<bool> writeCover(
    String filePath,
    Uint8List coverData, {
    String mimeType = 'image/jpeg',
  }) async => writeMetadata(
    filePath,
    WritableMetadata(coverData: coverData, coverMimeType: mimeType),
  );

  @override
  Future<bool> removeAllMetadata(String filePath) async {
    await _ensureInitialized();

    if (_toneAvailable) {
      try {
        final result = await Process.run(_tonePath!, [
          'tag',
          filePath,
          '--remove-all',
        ]);
        return result.exitCode == 0;
      } catch (e) {
        logger.e('FFmpegMetadataWriter: 清除元数据失败', e);
      }
    }

    if (_ffmpegAvailable) {
      try {
        final ext = p.extension(filePath);
        final tempOutput = '${filePath}_temp$ext';

        final result = await Process.run('ffmpeg', [
          '-y',
          '-i', filePath,
          '-c', 'copy',
          '-map_metadata', '-1', // 移除所有元数据
          tempOutput,
        ]);

        if (result.exitCode == 0) {
          await File(tempOutput).rename(filePath);
          return true;
        }
      } catch (e) {
        logger.e('FFmpegMetadataWriter: 清除元数据失败', e);
      }
    }

    // 使用 FFmpegKit（移动平台 + macOS）
    if (_ffmpegKitAvailable) {
      try {
        final ext = p.extension(filePath);
        final tempOutput = '${filePath}_temp$ext';

        final command = [
          '-y',
          '-i',
          _escapeFFmpegPath(filePath),
          '-c',
          'copy',
          '-map_metadata',
          '-1',
          _escapeFFmpegPath(tempOutput),
        ].join(' ');

        final session = await FFmpegKit.execute(command);
        final returnCode = await session.getReturnCode();

        if (ReturnCode.isSuccess(returnCode)) {
          await File(tempOutput).rename(filePath);
          return true;
        } else {
          // 清理临时文件
          try {
            await File(tempOutput).delete();
          } catch (e, st) {
            AppError.ignore(e, st, '清除元数据失败后清理临时文件失败');
          }
        }
      } catch (e) {
        logger.e('FFmpegMetadataWriter: FFmpegKit 清除元数据失败', e);
      }
    }

    return false;
  }

  /// 获取工具可用性状态
  Future<Map<String, dynamic>> getToolStatus() async {
    await _ensureInitialized();
    return {
      'ffmpeg': _ffmpegAvailable,
      'ffmpegKit': _ffmpegKitAvailable,
      'tone': _toneAvailable,
      'anyAvailable': _ffmpegAvailable || _ffmpegKitAvailable || _toneAvailable,
    };
  }
}
