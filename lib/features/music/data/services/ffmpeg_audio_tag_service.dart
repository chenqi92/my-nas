import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/music_tag_writer_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// FFmpeg 音频标签写入服务
///
/// 使用 FFmpeg 写入音频元数据，特别针对 FLAC 文件。
/// 相比 audio_metadata_reader 库，FFmpeg 写入的文件保持更好的兼容性，
/// 特别是在 iOS AVFoundation 上不会出现 -11800 解码错误。
class FfmpegAudioTagService {

  factory FfmpegAudioTagService() => _instance ??= FfmpegAudioTagService._();
  FfmpegAudioTagService._();

  static FfmpegAudioTagService? _instance;

  Directory? _tempDir;
  bool _initialized = false;

  /// 初始化服务
  Future<void> init() async {
    if (_initialized) return;

    _tempDir = await getTemporaryDirectory();
    _initialized = true;
    logger.d('FfmpegAudioTagService: 初始化完成');
  }

  /// 使用 FFmpeg 写入 FLAC 标签
  ///
  /// FFmpeg 命令: ffmpeg -i input.flac -c:a copy -metadata title="..." output.flac
  /// 只复制音频流不重编码，保持文件结构完整，确保 iOS AVFoundation 兼容性。
  ///
  /// [inputFile] 输入的 FLAC 文件
  /// [tagData] 要写入的元数据
  /// [coverFile] 可选的封面图片文件
  ///
  /// 返回写入结果
  Future<MusicTagWriteResult> writeFlacTags(
    File inputFile,
    MusicTagData tagData, {
    File? coverFile,
  }) async {
    if (!_initialized) await init();

    try {
      final updatedFields = <String>[];
      // 使用正确的扩展名，FFmpeg 需要根据扩展名确定输出格式
      // 例如: input.flac -> input_ffmpeg_tmp.flac
      final ext = p.extension(inputFile.path); // .flac
      final basePath = inputFile.path.substring(0, inputFile.path.length - ext.length);
      final tempOutput = File('${basePath}_ffmpeg_tmp$ext');

      // 构建 FFmpeg 参数
      final args = <String>[
        '-i',
        inputFile.path,
      ];

      // 如果有封面图片，添加图片输入
      if (coverFile != null && await coverFile.exists()) {
        args.addAll(['-i', coverFile.path]);
      }

      // 映射流
      args.addAll(['-map', '0:a']); // 只映射音频流

      // 如果有封面，映射图片作为附加图片
      if (coverFile != null && await coverFile.exists()) {
        args.addAll(['-map', '1:v?']); // 可选映射封面图片
      }

      // 复制音频流（不重编码）
      args.addAll(['-c:a', 'copy']);

      // 如果有封面，设置封面编解码器
      if (coverFile != null && await coverFile.exists()) {
        args
          ..addAll(['-c:v', 'copy'])
          ..addAll([
            '-disposition:v:0',
            'attached_pic',
          ]); // 标记为附加图片
        updatedFields.add(appL10n.ffmpegAudioTagFieldCover);
      }

      // 添加元数据
      final title = tagData.title;
      if (title != null && title.isNotEmpty) {
        args.addAll(['-metadata', 'title=$title']);
        updatedFields.add(appL10n.ffmpegAudioTagFieldTitle);
      }

      final artist = tagData.artist;
      if (artist != null && artist.isNotEmpty) {
        args.addAll(['-metadata', 'artist=$artist']);
        updatedFields.add(appL10n.ffmpegAudioTagFieldArtist);
      }

      final album = tagData.album;
      if (album != null && album.isNotEmpty) {
        args.addAll(['-metadata', 'album=$album']);
        updatedFields.add(appL10n.ffmpegAudioTagFieldAlbum);
      }

      final albumArtist = tagData.albumArtist;
      if (albumArtist != null && albumArtist.isNotEmpty) {
        args.addAll(['-metadata', 'album_artist=$albumArtist']);
        updatedFields.add(appL10n.ffmpegAudioTagFieldAlbumArtist);
      }

      final year = tagData.year;
      if (year != null) {
        args.addAll(['-metadata', 'date=$year']);
        updatedFields.add(appL10n.ffmpegAudioTagFieldYear);
      }

      final trackNumber = tagData.trackNumber;
      if (trackNumber != null) {
        args.addAll(['-metadata', 'track=$trackNumber']);
        updatedFields.add(appL10n.ffmpegAudioTagFieldTrackNumber);
      }

      final discNumber = tagData.discNumber;
      if (discNumber != null) {
        args.addAll(['-metadata', 'disc=$discNumber']);
        updatedFields.add(appL10n.ffmpegAudioTagFieldDiscNumber);
      }

      final genre = tagData.genre;
      if (genre != null && genre.isNotEmpty) {
        args.addAll(['-metadata', 'genre=$genre']);
        updatedFields.add(appL10n.ffmpegAudioTagFieldGenre);
      }

      // 注意：FLAC 的 Vorbis Comment 不直接支持歌词字段
      // 歌词通常存储在单独的 .lrc 文件中

      // 输出文件（覆盖）
      args.addAll(['-y', tempOutput.path]);

      logger.d('FfmpegAudioTagService: 执行 FFmpeg 命令: ffmpeg ${args.join(' ')}');

      // 执行 FFmpeg
      final session = await FFmpegKit.executeWithArguments(args);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        // 替换原文件
        if (await inputFile.exists()) {
          await inputFile.delete();
        }
        await tempOutput.rename(inputFile.path);

        logger.i('FfmpegAudioTagService: FLAC 标签写入成功, 更新字段: $updatedFields');
        return MusicTagWriteResult.success(updatedFields);
      } else {
        // 获取错误日志
        final logs = await session.getAllLogsAsString();
        final errorSnippet =
            logs != null && logs.length > 500 ? logs.substring(logs.length - 500) : logs ?? '';

        logger
          ..e('FfmpegAudioTagService: FFmpeg 写入失败')
          ..e('FfmpegAudioTagService: 错误日志: $errorSnippet');

        // 清理临时文件
        if (await tempOutput.exists()) {
          await tempOutput.delete();
        }

        return MusicTagWriteResult.failure(
            appL10n.ffmpegAudioTagWriteFailedWithCode('$returnCode'));
      }
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'FfmpegAudioTagService.writeFlacTags');
      return MusicTagWriteResult.failure(appL10n.ffmpegAudioTagWriteException(e));
    }
  }

  /// 修复损坏的 FLAC 文件
  ///
  /// 使用 FFmpeg 重新复制文件以修复结构问题。
  /// 这对于被 audio_metadata_reader 修改后无法在 iOS 播放的文件特别有用。
  ///
  /// 命令: ffmpeg -i input.flac -c:a copy -map_metadata 0 output.flac
  ///
  /// [inputFile] 损坏的 FLAC 文件
  /// [outputFile] 修复后的输出文件（可以与输入相同路径）
  ///
  /// 如果 outputFile 与 inputFile 相同，会先输出到临时文件再替换
  Future<bool> repairFlacFile(File inputFile, File outputFile) async {
    if (!_initialized) await init();

    try {
      final isSameFile = inputFile.path == outputFile.path;
      final actualOutput = isSameFile
          ? File(p.join(_tempDir!.path, 'repair_${DateTime.now().millisecondsSinceEpoch}.flac'))
          : outputFile;

      final args = <String>[
        '-i',
        inputFile.path,
        '-c:a',
        'copy', // 只复制，不重编码
        '-c:v',
        'copy', // 如果有封面也复制
        '-map_metadata',
        '0', // 保留原有元数据
        '-y',
        actualOutput.path,
      ];

      logger
        ..d('FfmpegAudioTagService: 修复 FLAC 文件: ${inputFile.path}')
        ..d('FfmpegAudioTagService: FFmpeg 命令: ffmpeg ${args.join(' ')}');

      final session = await FFmpegKit.executeWithArguments(args);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        // 如果是同一个文件，替换原文件
        if (isSameFile) {
          await inputFile.delete();
          await actualOutput.rename(outputFile.path);
        }

        logger.i('FfmpegAudioTagService: FLAC 文件修复成功');
        return true;
      } else {
        final logs = await session.getAllLogsAsString();
        logger.e('FfmpegAudioTagService: FLAC 文件修复失败: $logs');

        // 清理临时文件
        if (isSameFile && await actualOutput.exists()) {
          await actualOutput.delete();
        }
        return false;
      }
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'FfmpegAudioTagService.repairFlacFile');
      return false;
    }
  }

  /// 检查 FFmpeg 是否可用
  Future<bool> isAvailable() async {
    try {
      final session = await FFmpegKit.execute('-version');
      final returnCode = await session.getReturnCode();
      return ReturnCode.isSuccess(returnCode);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'FFmpeg 可用性检查失败');
      return false;
    }
  }
}
