import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart'
    show MetadataParserException, NoMetadataParserException, readMetadata;
import 'package:enough_convert/enough_convert.dart';
import 'package:flutter/foundation.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/ncm_decrypt_service.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 音乐元数据服务
/// 用于从音频文件中提取 ID3 标签等元数据
///
/// 特性：
/// - 使用 Isolate 隔离元数据提取，防止崩溃影响主应用
/// - Windows 平台特殊处理，确保临时文件正确写入
/// - 超时保护，防止单个文件卡住整个扫描
/// - 大文件保护，防止内存溢出
/// - 格式特定的智能读取策略
class MusicMetadataService {
  factory MusicMetadataService() => _instance ??= MusicMetadataService._();
  MusicMetadataService._();

  static MusicMetadataService? _instance;

  late Directory _cacheDir;
  bool _initialized = false;

  /// 已缓存的元数据（按路径索引）
  final Map<String, MusicMetadata> _metadataCache = {};

  /// 元数据提取超时时间
  static const _extractionTimeout = Duration(seconds: 30);

  // ==================== 文件大小限制常量 ====================

  /// 最小有效音频文件大小（100 字节）
  /// 小于此大小的文件被认为是无效或损坏的
  static const _minValidFileSize = 100;

  /// 绝对最大读取量（8MB）
  /// 无论何种格式，单次读取不超过此值
  static const _absoluteMaxReadSize = 8 * 1024 * 1024;

  /// 大文件阈值（50MB）
  /// 超过此大小的文件使用保守读取策略
  static const _largeFileThreshold = 50 * 1024 * 1024;

  /// 超大文件阈值（200MB）
  /// 超过此大小的文件只读取最小必要数据
  static const _veryLargeFileThreshold = 200 * 1024 * 1024;

  /// NCM 文件最大处理大小（100MB）
  static const _maxNcmSize = 100 * 1024 * 1024;

  // ==================== 格式特定读取配置 ====================

  /// 各格式的元数据读取配置
  /// - maxRead: 该格式建议的最大读取量
  /// - metadataInHeader: 元数据是否主要在文件头部
  /// - needsTail: 是否可能需要读取文件尾部（如 ID3v1）
  static const Map<String, _FormatConfig> _formatConfigs = {
    // 有损压缩格式
    '.mp3': _FormatConfig(
      maxRead: 4 * 1024 * 1024, // 4MB，ID3v2 + 封面
      metadataInHeader: true,
      needsTail: true, // ID3v1 在尾部
      tailSize: 128, // ID3v1 固定 128 字节
    ),
    '.aac': _FormatConfig(maxRead: 2 * 1024 * 1024, metadataInHeader: true),
    '.m4a': _FormatConfig(
      maxRead: 4 * 1024 * 1024, // moov atom 可能较大
      metadataInHeader: true, // 通常在开头，但也可能在结尾
    ),
    '.wma': _FormatConfig(maxRead: 2 * 1024 * 1024, metadataInHeader: true),
    '.ogg': _FormatConfig(maxRead: 2 * 1024 * 1024, metadataInHeader: true),
    '.opus': _FormatConfig(maxRead: 2 * 1024 * 1024, metadataInHeader: true),

    // 无损压缩格式
    '.flac': _FormatConfig(
      maxRead: 4 * 1024 * 1024, // FLAC 封面可能较大
      metadataInHeader: true,
      durationInHeader: true, // STREAMINFO 在开头，时长准确
    ),
    '.ape': _FormatConfig(
      maxRead: 4 * 1024 * 1024,
      metadataInHeader: true,
      needsTail: true, // APEv2 可能在尾部
      tailSize: 32 * 1024, // APEv2 标签通常不超过 32KB
    ),
    '.alac': _FormatConfig(maxRead: 4 * 1024 * 1024, metadataInHeader: true),

    // 无压缩/特殊格式
    '.wav': _FormatConfig(
      maxRead: 1 * 1024 * 1024, // WAV 元数据简单，1MB 足够
      metadataInHeader: true,
      durationInHeader: true,
    ),
    '.aiff': _FormatConfig(maxRead: 2 * 1024 * 1024, metadataInHeader: true),

    // DSD 格式（高质量音频，文件通常很大）
    '.dsf': _FormatConfig(
      maxRead: 2 * 1024 * 1024,
      metadataInHeader: true,
      durationInHeader: true,
    ),
    '.dff': _FormatConfig(
      maxRead: 2 * 1024 * 1024,
      metadataInHeader: true,
      durationInHeader: true,
    ),
    '.dsd': _FormatConfig(maxRead: 2 * 1024 * 1024, metadataInHeader: true),

    // Matroska 音频
    '.mka': _FormatConfig(maxRead: 4 * 1024 * 1024, metadataInHeader: true),
  };

  /// 默认格式配置（用于未知格式）
  static const _defaultFormatConfig = _FormatConfig(
    maxRead: 4 * 1024 * 1024,
    metadataInHeader: true,
  );

  /// 初始化服务
  Future<void> init() async {
    if (_initialized) return;

    final appDir = await getApplicationSupportDirectory();
    _cacheDir = Directory(p.join(appDir.path, 'music_metadata_cache'));
    if (!await _cacheDir.exists()) {
      await _cacheDir.create(recursive: true);
    }

    // 清理旧的临时文件
    await _cleanupTempFiles();

    _initialized = true;
    logger.i('MusicMetadataService: 初始化完成，缓存目录: ${_cacheDir.path}');
  }

  /// 清理遗留的临时文件
  Future<void> _cleanupTempFiles() async {
    try {
      final files = _cacheDir.listSync();
      for (final entity in files) {
        if (entity is File &&
            (p.basename(entity.path).startsWith('temp_metadata_') ||
                p.basename(entity.path).startsWith('temp_duration_'))) {
          try {
            await entity.delete();
          } catch (_) {
            // 忽略删除失败
          }
        }
      }
    } catch (e) {
      logger.d('MusicMetadataService: 清理临时文件失败: $e');
    }
  }

  /// 从本地文件提取元数据
  Future<MusicMetadata?> extractFromLocalFile(File file) async {
    if (!_initialized) await init();

    final cacheKey = file.path;
    if (_metadataCache.containsKey(cacheKey)) {
      logger.d('MusicMetadataService: 使用缓存的元数据: ${file.path}');
      return _metadataCache[cacheKey];
    }

    try {
      logger.i('MusicMetadataService: 开始提取本地文件元数据: ${file.path}');

      // 边界条件：检查文件是否存在
      if (!await file.exists()) {
        logger.w('MusicMetadataService: 文件不存在: ${file.path}');
        return _parseMetadataFromFilename(file.path);
      }

      final fileSize = await file.length();
      logger.d('MusicMetadataService: 文件大小 = $fileSize bytes');

      // 边界条件：空文件或极小文件
      if (fileSize < _minValidFileSize) {
        logger.w('MusicMetadataService: 文件过小，可能无效: ${file.path} ($fileSize bytes)');
        return _parseMetadataFromFilename(file.path);
      }

      // 使用 Isolate 隔离提取，防止崩溃
      final rawMetadata = await _readMetadataIsolated(file.path);
      if (rawMetadata == null) {
        logger.i('MusicMetadataService: 文件无元数据标签，使用文件名回退: ${file.path}');
        final fallback = _parseMetadataFromFilename(file.path);
        _metadataCache[cacheKey] = fallback;
        return fallback;
      }

      final result = _convertRawMetadata(rawMetadata, file.path);
      _metadataCache[cacheKey] = result;

      logger.i('MusicMetadataService: 提取完成 - hasCover=${result.hasCover}, hasLyrics=${result.hasLyrics}');
      return result;
    } catch (e, stackTrace) {
      logger.e('MusicMetadataService: 提取元数据失败: ${file.path}', e, stackTrace);
      return _parseMetadataFromFilename(file.path);
    }
  }

  /// 从 NAS 文件提取元数据
  /// 使用智能读取策略：根据格式和文件大小决定读取量
  /// [skipLyrics] 为 true 时跳过歌词提取，用于后台批量扫描
  Future<MusicMetadata?> extractFromNasFile(
    NasFileSystem fileSystem,
    String path, {
    bool skipLyrics = false,
  }) async {
    if (!_initialized) await init();

    final cacheKey = '${fileSystem.hashCode}_$path';
    if (_metadataCache.containsKey(cacheKey)) {
      return _metadataCache[cacheKey];
    }

    try {
      final ext = p.extension(path).toLowerCase();
      logger.d('MusicMetadataService: 提取 NAS 文件元数据: $path (ext: $ext)');

      // NCM 文件使用专门的解密服务
      if (ext == '.ncm') {
        return _extractFromNcmFile(fileSystem, path, cacheKey);
      }

      // 获取文件信息
      final fileInfo = await fileSystem.getFileInfo(path);
      final fileSize = fileInfo.size;

      // 边界条件：空文件或极小文件
      if (fileSize < _minValidFileSize) {
        logger.w('MusicMetadataService: 文件过小，可能无效: $path ($fileSize bytes)');
        final fallback = _parseMetadataFromFilename(path);
        _metadataCache[cacheKey] = fallback;
        return fallback;
      }

      // 获取格式配置
      final config = _formatConfigs[ext] ?? _defaultFormatConfig;

      // 计算读取策略
      final readSizes = _calculateReadSizes(fileSize, config);
      logger.d('MusicMetadataService: 文件大小=$fileSize, 读取策略=$readSizes');

      // 尝试各个读取大小
      for (final bytesToRead in readSizes) {
        final result = await _tryExtractMetadata(
          fileSystem,
          path,
          bytesToRead,
          cacheKey,
          skipLyrics: skipLyrics,
          actualFileSize: fileSize,
          formatConfig: config,
        );

        if (result != null) {
          return result;
        }

        // 如果已经读取了整个文件还是失败，不再重试
        if (bytesToRead >= fileSize) {
          logger.w('MusicMetadataService: 读取整个文件后仍无法解析元数据: $path');
          break;
        }

        logger.d('MusicMetadataService: 尝试更大的读取大小: $path');
      }

      // 所有尝试都失败，使用文件名作为回退
      logger.i('MusicMetadataService: 使用文件名回退解析: $path');
      final fallback = _parseMetadataFromFilename(path);
      _metadataCache[cacheKey] = fallback;
      return fallback;
    } catch (e, stackTrace) {
      // 使用通用 catch 捕获所有类型的异常
      logger.w('MusicMetadataService: 提取 NAS 文件元数据失败: $path', e, stackTrace);
      // 返回基于文件名的回退结果，而不是 null
      final fallback = _parseMetadataFromFilename(path);
      _metadataCache[cacheKey] = fallback;
      return fallback;
    }
  }

  /// 计算读取策略
  /// 返回应该尝试的读取大小列表（从小到大）
  ///
  /// 对于需要尾部数据的格式（如 MP3 的 ID3v1），优先尝试读取整个文件
  /// 因为简单拼接头部+尾部会破坏文件结构导致解析错误
  List<int> _calculateReadSizes(int fileSize, _FormatConfig config) {
    final sizes = <int>[];

    // 根据文件大小调整策略
    if (fileSize <= config.maxRead) {
      // 小文件：直接读取整个文件
      sizes.add(fileSize);
    } else if (fileSize <= _largeFileThreshold) {
      // 中等文件（<50MB）

      // 对于可能需要尾部数据的格式（如 MP3），优先尝试读取整个文件
      // 因为无法简单拼接头部和尾部数据
      if (config.needsTail && fileSize <= _absoluteMaxReadSize) {
        // 文件小于 8MB，直接读取整个文件
        sizes.add(fileSize);
      } else {
        // 渐进式读取
        sizes.add(1 * 1024 * 1024); // 1MB
        if (config.maxRead > 1 * 1024 * 1024) {
          sizes.add(2 * 1024 * 1024); // 2MB
        }
        if (config.maxRead > 2 * 1024 * 1024) {
          sizes.add(config.maxRead); // 格式建议的最大值
        }
        // 如果还没成功，尝试读取整个文件（但不超过绝对上限）
        final fullRead = fileSize < _absoluteMaxReadSize ? fileSize : _absoluteMaxReadSize;
        if (!sizes.contains(fullRead)) {
          sizes.add(fullRead);
        }
      }
    } else if (fileSize <= _veryLargeFileThreshold) {
      // 大文件（50-200MB）：限制读取量
      // 对于这种大小的文件，大多数元数据应该在 ID3v2（文件开头）
      sizes
        ..add(2 * 1024 * 1024) // 2MB
        ..add(4 * 1024 * 1024) // 4MB
        ..add(_absoluteMaxReadSize); // 最大 8MB
    } else {
      // 超大文件（>200MB）：只读取最小必要数据
      // 对于这些文件（如大型 WAV/DSD），元数据肯定在开头
      sizes
        ..add(1 * 1024 * 1024) // 1MB
        ..add(2 * 1024 * 1024); // 2MB
      // 不再增加，避免内存问题
    }

    return sizes;
  }

  /// 尝试使用指定大小提取元数据
  Future<MusicMetadata?> _tryExtractMetadata(
    NasFileSystem fileSystem,
    String path,
    int bytesToRead,
    String cacheKey, {
    required int actualFileSize,
    required _FormatConfig formatConfig,
    bool skipLyrics = false,
  }) async {
    File? tempFile;
    RandomAccessFile? raf;
    try {
      logger.d('MusicMetadataService: 尝试读取 $bytesToRead 字节: $path');

      // 读取文件头部
      final stream = await fileSystem.getFileStream(
        path,
        range: FileRange(start: 0, end: bytesToRead),
      );

      // 使用 BytesBuilder 优化内存分配
      final bytesBuilder = BytesBuilder(copy: false);
      await for (final chunk in stream) {
        bytesBuilder.add(chunk);
        // 内存保护：如果数据量超过预期太多，中止
        if (bytesBuilder.length > bytesToRead * 1.5) {
          logger.w('MusicMetadataService: 数据量超出预期，中止读取: $path');
          break;
        }
      }

      final data = bytesBuilder.toBytes();

      // 注意：不再简单拼接头部和尾部数据
      // 原因：audio_metadata_reader 库期望连续的文件流，简单拼接会导致：
      // - 文件结构断裂，解析器在读取"中间"数据时遇到尾部数据
      // - UTF-8 解析错误（如 FormatException: Unfinished UTF-8 octet sequence）
      //
      // 对于 MP3 文件：
      // - ID3v2 在文件开头（我们已经读取）
      // - ID3v1 在文件末尾（128字节），但大多数现代文件使用 ID3v2
      // - 如果头部数据不足以提取元数据，调用者会重试更大的读取大小
      //
      // 如果确实需要完整的尾部标签，应该读取整个文件而不是拼接

      // 保存到临时文件（使用唯一文件名避免并发冲突）
      final ext = p.extension(path).toLowerCase();
      final uniqueId = '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(999999)}';
      tempFile = File(p.join(_cacheDir.path, 'temp_metadata_$uniqueId$ext'));

      // Windows 特殊处理：使用 RandomAccessFile 确保数据完全写入
      if (Platform.isWindows) {
        raf = await tempFile.open(mode: FileMode.writeOnly);
        await raf.writeFrom(data);
        await raf.flush(); // 确保数据写入磁盘
        await raf.close();
        raf = null;
        // Windows 上等待文件系统同步
        await Future<void>.delayed(const Duration(milliseconds: 50));
      } else {
        await tempFile.writeAsBytes(data, flush: true);
      }

      // 使用 Isolate 隔离提取，带超时保护
      final rawMetadata = await _readMetadataIsolated(tempFile.path).timeout(
        _extractionTimeout,
        onTimeout: () {
          logger.w('MusicMetadataService: 元数据提取超时: $path');
          return null;
        },
      );

      if (rawMetadata == null) {
        // 无元数据或解析失败
        return null;
      }

      // 判断是否需要跳过 duration
      final isPartialRead = bytesToRead < actualFileSize;
      final skipDuration = isPartialRead && !formatConfig.durationInHeader;
      final result = _convertRawMetadata(
        rawMetadata,
        path,
        skipLyrics: skipLyrics,
        skipDuration: skipDuration,
      );
      _metadataCache[cacheKey] = result;

      logger.d('MusicMetadataService: 成功提取元数据 (读取 $bytesToRead 字节): $path');
      return result;
    } on MetadataParserException catch (e) {
      // 解析异常，可能需要更多数据
      if (e.toString().contains('Expected more data')) {
        logger.d('MusicMetadataService: 数据不足，需要读取更多: $path');
        return null; // 返回 null 让调用者重试更大的大小
      }
      // 其他解析异常，记录但不抛出
      logger.d('MusicMetadataService: 解析异常: $path - $e');
      return null;
    } catch (e) {
      // 使用通用 catch 捕获所有类型的异常（包括 String 异常）
      logger.d('MusicMetadataService: 提取失败: $path - $e');
      return null;
    } finally {
      // 确保关闭文件句柄
      try {
        await raf?.close();
      } catch (e, st) {
        AppError.ignore(e, st, '关闭随机访问文件句柄失败');
      }
      // 清理临时文件
      if (tempFile != null) {
        await _deleteTempFile(tempFile);
      }
    }
  }

  /// 在 Isolate 中读取元数据（防止崩溃影响主应用）
  ///
  /// 返回原始元数据 Map，如果失败返回 null
  Future<Map<String, dynamic>?> _readMetadataIsolated(String filePath) async {
    try {
      // 使用 compute 在独立 Isolate 中运行
      return await compute(_readMetadataInIsolate, filePath);
    } catch (e) {
      // 捕获 Isolate 中的任何崩溃
      logger.w('MusicMetadataService: Isolate 元数据提取失败: $filePath - $e');
      return null;
    }
  }

  /// 从 NCM 文件提取元数据
  Future<MusicMetadata?> _extractFromNcmFile(
    NasFileSystem fileSystem,
    String path,
    String cacheKey,
  ) async {
    try {
      logger.d('MusicMetadataService: 开始解密 NCM 文件: $path');

      // 获取文件大小，限制最大处理大小（防止内存溢出）
      final fileInfo = await fileSystem.getFileInfo(path);

      // 边界条件：检查文件大小
      if (fileInfo.size < _minValidFileSize) {
        logger.w('MusicMetadataService: NCM 文件过小: $path');
        return _parseMetadataFromFilename(path);
      }

      if (fileInfo.size > _maxNcmSize) {
        logger.w('MusicMetadataService: NCM 文件过大，跳过: $path (${fileInfo.size} bytes)');
        return _parseMetadataFromFilename(path);
      }

      // 下载整个 NCM 文件（NCM 文件需要完整读取才能解密）
      final stream = await fileSystem.getFileStream(path);
      final bytesBuilder = BytesBuilder(copy: false);
      await for (final chunk in stream) {
        bytesBuilder.add(chunk);
        // 内存保护
        if (bytesBuilder.length > _maxNcmSize) {
          logger.w('MusicMetadataService: NCM 文件读取超出限制: $path');
          return _parseMetadataFromFilename(path);
        }
      }

      final ncmData = bytesBuilder.toBytes();
      logger.d('MusicMetadataService: NCM 文件大小: ${ncmData.length} bytes');

      // 解密 NCM 文件（在 Isolate 中执行以隔离潜在崩溃）
      final result = await compute(_decryptNcmInIsolate, ncmData).timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          logger.w('MusicMetadataService: NCM 解密超时: $path');
          return null;
        },
      );

      if (result == null) {
        logger.w('MusicMetadataService: NCM 解密失败: $path');
        return _parseMetadataFromFilename(path);
      }

      // 从解密结果中提取元数据
      final metadata = MusicMetadata(
        title: result['title'] as String?,
        artist: result['artist'] as String?,
        album: result['album'] as String?,
        duration: result['duration'] != null ? Duration(milliseconds: result['duration'] as int) : null,
        coverData: result['coverData'] as List<int>?,
      );

      _metadataCache[cacheKey] = metadata;
      logger.i('MusicMetadataService: NCM 元数据提取成功 - ${metadata.title}');
      return metadata;
    } catch (e, stackTrace) {
      logger.e('MusicMetadataService: NCM 文件处理失败: $path', e, stackTrace);
      return _parseMetadataFromFilename(path);
    }
  }

  /// 安全删除临时文件
  ///
  /// Windows 上 audio_metadata_reader 库可能延迟释放文件句柄，
  /// 需要更长的等待时间和更多重试次数
  Future<void> _deleteTempFile(File tempFile) async {
    // Windows 上延迟删除，确保文件句柄已释放
    // audio_metadata_reader 内部可能有缓冲区需要时间释放
    if (Platform.isWindows) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    // 最多重试 5 次，使用指数退避
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        return;
      } catch (e) {
        if (attempt < 4) {
          // 指数退避：100ms, 200ms, 400ms, 800ms
          final delay = Duration(milliseconds: 100 * (1 << attempt));
          await Future<void>.delayed(delay);
        } else {
          // 最后一次失败，记录并添加到待清理列表
          // 文件会在下次服务初始化时被清理
          logger.d('MusicMetadataService: 临时文件删除失败，将在下次启动时清理: ${tempFile.path}');
        }
      }
    }
  }

  /// 将原始元数据 Map 转换为 MusicMetadata
  MusicMetadata _convertRawMetadata(
    Map<String, dynamic> raw,
    String filePath, {
    bool skipLyrics = false,
    bool skipDuration = false,
  }) =>
      MusicMetadata(
        title: _fixEncoding(raw['title'] as String?),
        artist: _fixEncoding(raw['artist'] as String?),
        album: _fixEncoding(raw['album'] as String?),
        trackNumber: raw['trackNumber'] as int?,
        year: raw['year'] as int?,
        genre: _fixEncoding(raw['genre'] as String?),
        lyrics: skipLyrics ? null : _fixEncoding(raw['lyrics'] as String?),
        coverData: raw['coverData'] as List<int>?,
        duration: skipDuration ? null : (raw['duration'] as Duration?),
      );

  /// 修复可能被错误解码的字符串编码
  ///
  /// 问题场景：GBK 编码的中文被错误地用 Latin-1 解码
  /// 例如："曲目" (GBK: C7 FA C4 BF) → "ÇúÄ¿" (Latin-1 解码)
  ///
  /// 修复方法：
  /// 1. 检测是否包含高位 Latin-1 字符（典型乱码特征）
  /// 2. 将字符串转回 Latin-1 字节
  /// 3. 用 GBK 重新解码
  String? _fixEncoding(String? text) {
    if (text == null || text.isEmpty) return text;

    // 如果已经是有效的中文或纯 ASCII，无需修复
    if (_containsChinese(text) || _isPureAscii(text)) {
      return text;
    }

    // 检测是否是 GBK 乱码（Latin-1 高位字符特征）
    if (!_looksLikeGbkMojibake(text)) {
      return text;
    }

    try {
      // 将 Latin-1 字符串转回字节
      final bytes = latin1.encode(text);

      // 尝试用 GBK 解码
      const gbkCodec = GbkCodec(allowInvalid: false);
      final decoded = gbkCodec.decode(bytes);

      // 验证解码结果
      if (decoded.isNotEmpty && _containsChinese(decoded)) {
        logger.d('MusicMetadataService: 编码修复成功 "$text" -> "$decoded"');
        return decoded;
      }
    } catch (e) {
      // GBK 解码失败，可能不是 GBK 编码
      logger.d('MusicMetadataService: 编码修复失败: $e');
    }

    return text;
  }

  /// 检测字符串是否像 GBK 乱码（Latin-1 解码的 GBK 字节）
  ///
  /// GBK 编码范围：0x8140-0xFEFE
  /// 当用 Latin-1 解码时，会产生 0x80-0xFF 范围的高位字符
  /// 常见特征字符：Ç(C7), ú(FA), Ä(C4), ¿(BF), É(C9), ê(EA) 等
  bool _looksLikeGbkMojibake(String text) {
    var highByteCount = 0;
    var consecutiveHighBytes = 0;
    var maxConsecutive = 0;

    for (final codeUnit in text.codeUnits) {
      if (codeUnit >= 0x80 && codeUnit <= 0xFF) {
        highByteCount++;
        consecutiveHighBytes++;
        if (consecutiveHighBytes > maxConsecutive) {
          maxConsecutive = consecutiveHighBytes;
        }
      } else {
        consecutiveHighBytes = 0;
      }
    }

    // GBK 乱码特征：
    // 1. 有一定数量的高位字符
    // 2. 高位字符通常成对出现（GBK 是双字节编码）
    final ratio = highByteCount / text.length;
    return highByteCount >= 2 && ratio > 0.3 && maxConsecutive >= 2;
  }

  /// 检查字符串是否包含中文字符
  bool _containsChinese(String text) {
    // 中文 Unicode 范围：\u4e00-\u9fff (CJK Unified Ideographs)
    final chineseRegex = RegExp(r'[\u4e00-\u9fff]');
    return chineseRegex.hasMatch(text);
  }

  /// 检查字符串是否是纯 ASCII
  bool _isPureAscii(String text) => text.codeUnits.every((c) => c < 128);

  /// 将元数据应用到 MusicItem
  /// 只更新缺失的字段，不覆盖已有的有效数据
  MusicItem applyMetadataToItem(MusicItem item, MusicMetadata metadata) => item.copyWith(
        artist: (item.artist?.isNotEmpty ?? false) ? item.artist : metadata.artist,
        album: (item.album?.isNotEmpty ?? false) ? item.album : metadata.album,
        trackNumber: item.trackNumber ?? metadata.trackNumber,
        year: item.year ?? metadata.year,
        genre: (item.genre?.isNotEmpty ?? false) ? item.genre : metadata.genre,
        lyrics: (item.lyrics?.isNotEmpty ?? false) ? item.lyrics : metadata.lyrics,
        coverData: (item.coverData?.isNotEmpty ?? false) ? item.coverData : metadata.coverData,
        duration: (item.duration != null && item.duration! > Duration.zero) ? item.duration : metadata.duration,
      );

  /// 从文件名解析元数据（用于无 ID3 标签的文件回退）
  /// 支持的格式:
  /// - "标题（艺术家）.mp3"
  /// - "标题 - 艺术家.mp3"
  /// - "艺术家 - 标题.mp3"
  /// - "标题.mp3"
  MusicMetadata _parseMetadataFromFilename(String path) {
    final filename = p.basenameWithoutExtension(path);

    // 边界条件：空文件名
    if (filename.isEmpty) {
      return MusicMetadata(title: appL10n.musicUnknownTrack);
    }

    String? title;
    String? artist;

    // 尝试匹配 "标题（艺术家）" 或 "标题(艺术家)" 格式
    final parenMatch = RegExp(r'^(.+?)[（(](.+?)[）)]$').firstMatch(filename);
    if (parenMatch != null) {
      title = parenMatch.group(1)?.trim();
      artist = parenMatch.group(2)?.trim();
    } else {
      // 尝试匹配 "A - B" 格式
      final dashMatch = RegExp(r'^(.+?)\s*[-–—]\s*(.+)$').firstMatch(filename);
      if (dashMatch != null) {
        final part1 = dashMatch.group(1)?.trim();
        final part2 = dashMatch.group(2)?.trim();
        // 通常是 "艺术家 - 标题" 格式，但也可能是 "标题 - 艺术家"
        // 这里我们假设第一部分是艺术家
        artist = part1;
        title = part2;
      } else {
        // 无法解析，使用整个文件名作为标题
        title = filename;
      }
    }

    // 边界条件：解析后仍为空
    if (title?.isEmpty ?? true) {
      title = filename.isNotEmpty ? filename : '未知曲目';
    }

    logger.d('MusicMetadataService: 从文件名解析 - title=$title, artist=$artist');

    return MusicMetadata(
      title: title,
      artist: artist,
    );
  }

  /// 清除缓存
  void clearCache() {
    _metadataCache.clear();
  }

  /// 专门获取音频时长（用于播放时获取准确时长）
  /// 会尝试读取足够的数据来获取准确的时长信息
  Future<Duration?> getDurationFromNasFile(
    NasFileSystem fileSystem,
    String path,
  ) async {
    if (!_initialized) await init();

    try {
      logger.d('MusicMetadataService: 获取音频时长: $path');

      // 获取文件信息
      final fileInfo = await fileSystem.getFileInfo(path);
      final fileSize = fileInfo.size;
      final ext = p.extension(path).toLowerCase();

      // 边界条件：空文件
      if (fileSize < _minValidFileSize) {
        return null;
      }

      // 获取格式配置
      final config = _formatConfigs[ext] ?? _defaultFormatConfig;

      // 对于时长在头部的格式（FLAC、WAV、DSD），读取较少数据
      // 对于其他格式，读取更多数据以获取准确时长
      int bytesToRead;
      if (config.durationInHeader) {
        bytesToRead = fileSize < 512 * 1024 ? fileSize : 512 * 1024;
      } else {
        // 对于 MP3 等格式，尝试读取更多数据
        // 但不超过 8MB 和文件大小
        bytesToRead = fileSize < _absoluteMaxReadSize ? fileSize : _absoluteMaxReadSize;
      }

      // 读取文件数据
      final stream = await fileSystem.getFileStream(
        path,
        range: FileRange(start: 0, end: bytesToRead),
      );

      final bytesBuilder = BytesBuilder(copy: false);
      await for (final chunk in stream) {
        bytesBuilder.add(chunk);
      }

      // 保存到临时文件
      final uniqueId = '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(999999)}';
      final tempFile = File(p.join(_cacheDir.path, 'temp_duration_$uniqueId$ext'));

      try {
        // Windows 特殊处理
        if (Platform.isWindows) {
          final raf = await tempFile.open(mode: FileMode.writeOnly);
          await raf.writeFrom(bytesBuilder.toBytes());
          await raf.flush();
          await raf.close();
          await Future<void>.delayed(const Duration(milliseconds: 50));
        } else {
          await tempFile.writeAsBytes(bytesBuilder.toBytes(), flush: true);
        }

        // 使用 Isolate 隔离提取
        final rawMetadata = await _readMetadataIsolated(tempFile.path).timeout(
          _extractionTimeout,
          onTimeout: () => null,
        );

        if (rawMetadata == null) {
          logger.w('MusicMetadataService: 无法获取时长');
          return null;
        }

        final duration = rawMetadata['duration'] as Duration?;

        if (duration != null && duration > Duration.zero) {
          logger.i('MusicMetadataService: 获取到时长: $duration (读取了 $bytesToRead 字节)');

          // 对于部分读取的非头部时长格式，根据实际文件大小调整时长估算
          if (!config.durationInHeader && bytesToRead < fileSize && duration.inSeconds > 0) {
            // 基于比特率估算完整文件时长
            final bytesPerSecond = bytesToRead / duration.inSeconds;
            final estimatedDuration = Duration(
              seconds: (fileSize / bytesPerSecond).round(),
            );
            logger.i('MusicMetadataService: 调整后的时长估算: $estimatedDuration');
            return estimatedDuration;
          }

          return duration;
        }

        logger.w('MusicMetadataService: 无法获取时长');
        return null;
      } finally {
        // 清理临时文件
        await _deleteTempFile(tempFile);
      }
    } catch (e, stackTrace) {
      logger.w('MusicMetadataService: 获取时长失败: $path', e, stackTrace);
      return null;
    }
  }
}

/// 格式配置
class _FormatConfig {
  const _FormatConfig({
    required this.maxRead,
    required this.metadataInHeader,
    this.needsTail = false,
    this.tailSize = 0,
    this.durationInHeader = false,
  });

  /// 建议的最大读取量
  final int maxRead;

  /// 元数据是否主要在文件头部
  final bool metadataInHeader;

  /// 是否可能需要读取文件尾部
  final bool needsTail;

  /// 尾部数据大小
  final int tailSize;

  /// 时长信息是否在文件头部（部分读取时仍准确）
  final bool durationInHeader;
}

/// 在 Isolate 中读取元数据的函数（顶层函数，可被 compute 调用）
///
/// 返回原始元数据 Map，如果失败返回 null
Map<String, dynamic>? _readMetadataInIsolate(String filePath) {
  try {
    final file = File(filePath);
    if (!file.existsSync()) {
      return null;
    }

    // 边界条件：检查文件大小
    final fileSize = file.lengthSync();
    if (fileSize < 100) {
      return null;
    }

    final metadata = readMetadata(file, getImage: true);

    // 将 AudioMetadata 转换为可序列化的 Map
    List<int>? coverData;
    if (metadata.pictures.isNotEmpty) {
      coverData = metadata.pictures.first.bytes.toList();
    }

    String? genre;
    if (metadata.genres.isNotEmpty) {
      genre = metadata.genres.join(', ');
    }

    return {
      'title': metadata.title,
      'artist': metadata.artist,
      'album': metadata.album,
      'trackNumber': metadata.trackNumber,
      'year': metadata.year?.year,
      'genre': genre,
      'lyrics': metadata.lyrics,
      'coverData': coverData,
      'duration': metadata.duration,
    };
  } on NoMetadataParserException {
    // 文件没有元数据标签
    return null;
  } catch (e) {
    // 捕获所有异常，防止 Isolate 崩溃
    // ignore: avoid_print
    print('MusicMetadataService: Isolate 中元数据提取异常: $e');
    return null;
  }
}

/// 在 Isolate 中解密 NCM 文件
Map<String, dynamic>? _decryptNcmInIsolate(Uint8List ncmData) {
  try {
    // 边界条件：数据过小
    if (ncmData.length < 100) {
      return null;
    }

    final ncmService = NcmDecryptService();
    final result = ncmService.decrypt(ncmData);

    if (result == null) {
      return null;
    }

    final ncmMeta = result.metadata;
    return {
      'title': ncmMeta?.musicName,
      'artist': ncmMeta?.artist,
      'album': ncmMeta?.album,
      'duration': ncmMeta != null && ncmMeta.duration > 0 ? ncmMeta.duration : null,
      'coverData': result.coverData?.toList(),
    };
  } catch (e) {
    // ignore: avoid_print
    print('MusicMetadataService: Isolate 中 NCM 解密异常: $e');
    return null;
  }
}

/// 音乐元数据
class MusicMetadata {
  const MusicMetadata({
    this.title,
    this.artist,
    this.album,
    this.trackNumber,
    this.year,
    this.genre,
    this.lyrics,
    this.coverData,
    this.duration,
  });

  final String? title;
  final String? artist;
  final String? album;
  final int? trackNumber;
  final int? year;
  final String? genre;
  final String? lyrics;
  final List<int>? coverData;
  final Duration? duration;

  bool get hasCover => coverData != null && coverData!.isNotEmpty;
  bool get hasLyrics => lyrics != null && lyrics!.isNotEmpty;
}
