import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/transfer/data/services/cache_config_service.dart';
import 'package:my_nas/features/transfer/domain/entities/transfer_task.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 音乐音频缓存服务 - 管理音乐文件的持久化缓存
/// 用于 LockCachingAudioSource 实现持久化缓存，避免重复下载
class MusicAudioCacheService {
  factory MusicAudioCacheService() => _instance ??= MusicAudioCacheService._();
  MusicAudioCacheService._();

  static MusicAudioCacheService? _instance;

  String? _cacheDir;
  bool _initialized = false;

  /// 默认缓存目录最大总大小（2GB），可通过 CacheConfigService 配置
  static const int defaultMaxCacheSize = 2 * 1024 * 1024 * 1024;

  /// 获取配置的缓存大小限制
  Future<int> _getMaxCacheSize() async {
    try {
      final configService = CacheConfigService();
      return await configService.getCacheSizeLimit(MediaType.music);
    } catch (_) {
      return defaultMaxCacheSize;
    }
  }

  /// 初始化缓存目录
  Future<void> init() async {
    if (_initialized) return;

    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      _cacheDir = p.join(documentsDir.path, 'music_audio_cache');

      final dir = Directory(_cacheDir!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      _initialized = true;
      logger.i('MusicAudioCacheService: 缓存目录初始化完成 $_cacheDir');
    } catch (e, st) {
      AppError.handle(e, st, 'MusicAudioCacheService.init');
      rethrow;
    }
  }

  /// 生成缓存文件的唯一键
  /// 使用 sourceId 和 filePath 组合生成，确保同一文件只缓存一次
  String _generateCacheKey(String? sourceId, String filePath) {
    final key = sourceId != null ? '${sourceId}_$filePath' : filePath;
    return md5.convert(utf8.encode(key)).toString();
  }

  /// 获取音频缓存文件路径
  /// 即使文件不存在也返回路径（用于 LockCachingAudioSource 创建缓存）
  Future<File> getCacheFile(String? sourceId, String filePath) async {
    if (!_initialized) await init();

    final hash = _generateCacheKey(sourceId, filePath);
    final extension = p.extension(filePath).toLowerCase();
    // 保留原始扩展名，便于识别文件类型
    final filename = '$hash$extension';
    return File(p.join(_cacheDir!, filename));
  }

  /// 检查缓存文件是否存在且完整
  /// 完整性检查：
  /// 1. 文件存在且大小 > 0
  /// 2. 没有对应的 .part 文件（表示下载已完成）
  /// 注意：LockCachingAudioSource 在下载时使用 .part 文件
  Future<bool> isCached(String? sourceId, String filePath) async {
    if (!_initialized) await init();

    try {
      final file = await getCacheFile(sourceId, filePath);
      if (await file.exists()) {
        final size = await file.length();
        if (size <= 0) return false;

        // 检查是否存在 .part 文件（表示下载未完成）
        // LockCachingAudioSource 在下载完成后会删除 .part 文件
        final partFile = File('${file.path}.part');
        if (await partFile.exists()) {
          logger.d('MusicAudioCache: 缓存文件存在但下载未完成 (.part 文件存在): ${file.path}');
          return false;
        }

        return true;
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '检查缓存失败，非关键功能');
    }
    return false;
  }
  
  /// 检查缓存文件是否存在、完整且大小大致正确
  /// 
  /// [expectedSize] 期望的文件大小（从 MusicItem 元数据获取）
  /// [tolerancePercent] 允许的大小误差百分比（默认 5%）
  /// 
  /// 使用百分比容差而非精确匹配的原因：
  /// 1. MusicItem 元数据可能来自自动/手动刮削，与实际文件大小有偏差
  /// 2. 真正损坏的文件通常会有显著的大小差异（如 50%+）
  /// 3. 小范围误差（<5%）通常表示元数据过时，而非文件损坏
  Future<bool> isCachedWithSizeCheck(
    String? sourceId,
    String filePath,
    int expectedSize, {
    double tolerancePercent = 5.0,
  }) async {
    if (!_initialized) await init();
    if (expectedSize <= 0) {
      // 没有预期大小时退回到普通检查
      return isCached(sourceId, filePath);
    }

    try {
      final file = await getCacheFile(sourceId, filePath);
      if (await file.exists()) {
        final actualSize = await file.length();
        if (actualSize <= 0) return false;

        // 检查是否存在 .part 文件
        final partFile = File('${file.path}.part');
        if (await partFile.exists()) {
          logger.d('MusicAudioCache: 缓存文件存在但下载未完成');
          return false;
        }

        // 使用百分比容差检查文件大小
        // 允许 tolerancePercent% 的误差，处理元数据不精确的情况
        final sizeDiffPercent = ((actualSize - expectedSize).abs() / expectedSize) * 100;
        if (sizeDiffPercent > tolerancePercent) {
          // 大小差异超过容差，可能是真正的损坏或完全不同的文件
          logger.w('MusicAudioCache: 缓存文件大小差异过大! '
              '期望=$expectedSize, 实际=$actualSize, 差异=${sizeDiffPercent.toStringAsFixed(1)}%');
          // 不自动删除，因为大小不匹配可能是元数据问题而非缓存损坏
          // 返回 false 让播放逻辑使用流式播放
          return false;
        }

        // 大小在容差范围内，记录日志供诊断
        if (sizeDiffPercent > 0.1) {
          logger.d('MusicAudioCache: 缓存大小有小偏差 (${sizeDiffPercent.toStringAsFixed(1)}%)，在容差范围内');
        }
        return true;
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '检查缓存失败，非关键功能');
    }
    return false;
  }


  /// 检查缓存文件是否正在下载中（有 .part 文件）
  Future<bool> isDownloading(String? sourceId, String filePath) async {
    if (!_initialized) await init();

    try {
      final file = await getCacheFile(sourceId, filePath);
      final partFile = File('${file.path}.part');
      return await partFile.exists();
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '检查下载状态失败，非关键功能');
    }
    return false;
  }

  /// 删除指定音乐的缓存
  Future<void> deleteCache(String? sourceId, String filePath) async {
    if (!_initialized) await init();

    try {
      final file = await getCacheFile(sourceId, filePath);
      if (await file.exists()) {
        await file.delete();
        logger.d('MusicAudioCacheService: 已删除缓存 ${file.path}');
      }

      // 同时删除 .part 文件（如果存在）
      final partFile = File('${file.path}.part');
      if (await partFile.exists()) {
        await partFile.delete();
      }

      // 删除 .mime 文件（如果存在）
      final mimeFile = File('${file.path}.mime');
      if (await mimeFile.exists()) {
        await mimeFile.delete();
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '删除缓存失败，非关键功能');
    }
  }

  /// 确保缓存不超过配额，必要时清理最旧的文件
  Future<void> ensureCacheQuota({int? newFileSize}) async {
    if (!_initialized) await init();

    final maxCacheSize = await _getMaxCacheSize();
    // 如果限制为 0，表示无限制
    if (maxCacheSize == 0) return;

    final requiredSize = newFileSize ?? 0;
    final currentSize = await getCacheSize();
    if (currentSize + requiredSize <= maxCacheSize) return;

    try {
      final dir = Directory(_cacheDir!);
      if (!await dir.exists()) return;

      // 获取所有缓存文件及其修改时间
      final files = <MapEntry<File, DateTime>>[];
      await for (final entity in dir.list()) {
        if (entity is File && !entity.path.endsWith('.part') && !entity.path.endsWith('.mime')) {
          final stat = await entity.stat();
          files.add(MapEntry(entity, stat.accessed));
        }
      }

      // 按访问时间排序（最旧的在前）
      files.sort((a, b) => a.value.compareTo(b.value));

      // 删除最旧的文件直到有足够空间
      var freedSize = 0;
      final targetFreeSize = (currentSize + requiredSize) - maxCacheSize;
      for (final entry in files) {
        if (freedSize >= targetFreeSize) break;

        try {
          final fileSize = await entry.key.length();
          final basePath = entry.key.path;

          // 删除主文件
          await entry.key.delete();
          freedSize += fileSize;

          // 同时删除关联的 .part 和 .mime 文件
          final partFile = File('$basePath.part');
          if (await partFile.exists()) {
            await partFile.delete();
          }
          final mimeFile = File('$basePath.mime');
          if (await mimeFile.exists()) {
            await mimeFile.delete();
          }

          logger.d('MusicAudioCacheService: 清理旧缓存 ${entry.key.path}');
        } on Exception catch (_) {
          // 忽略单个文件删除失败
        }
      }

      if (freedSize > 0) {
        logger.i(
          'MusicAudioCacheService: 已清理 '
          '${(freedSize / 1024 / 1024).toStringAsFixed(2)}MB 缓存空间',
        );
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '清理缓存配额失败，非关键功能');
    }
  }

  /// 清空所有音频缓存
  Future<void> clearAll() async {
    if (!_initialized) await init();

    try {
      final dir = Directory(_cacheDir!);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            await entity.delete();
          }
        }
      }
      logger.i('MusicAudioCacheService: 已清空所有音频缓存');
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'MusicAudioCacheService.clearAll');
    }
  }

  /// 获取缓存大小（字节）
  Future<int> getCacheSize() async {
    if (!_initialized) await init();

    var totalSize = 0;
    try {
      final dir = Directory(_cacheDir!);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            totalSize += await entity.length();
          }
        }
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '计算缓存大小失败，非关键功能');
    }
    return totalSize;
  }

  /// 获取格式化的缓存大小
  Future<String> getCacheSizeFormatted() async {
    final size = await getCacheSize();
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// 获取缓存文件数量
  Future<int> getCacheCount() async {
    if (!_initialized) await init();

    var count = 0;
    try {
      final dir = Directory(_cacheDir!);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File && !entity.path.endsWith('.part') && !entity.path.endsWith('.mime')) {
            count++;
          }
        }
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '计算缓存数量失败，非关键功能');
    }
    return count;
  }

  /// 获取缓存目录路径
  String? get cacheDirectory => _cacheDir;

  /// 获取所有缓存项列表
  /// 注意：由于使用哈希值存储，无法恢复原始路径，只返回文件信息
  Future<List<CachedMediaItem>> getCachedItems() async {
    if (!_initialized) await init();

    final items = <CachedMediaItem>[];
    try {
      final dir = Directory(_cacheDir!);
      if (!await dir.exists()) return items;

      // 先收集所有文件信息
      final fileInfos = <({File file, FileStat stat, String extension})>[];
      await for (final entity in dir.list()) {
        if (entity is File &&
            !entity.path.endsWith('.part') &&
            !entity.path.endsWith('.mime')) {
          final stat = await entity.stat();
          final extension = p.extension(entity.path).toLowerCase();
          fileInfos.add((file: entity, stat: stat, extension: extension));
        }
      }

      // 按访问时间排序（最新的在前）
      fileInfos.sort((a, b) => b.stat.accessed.compareTo(a.stat.accessed));

      // 排序后再编号
      for (var i = 0; i < fileInfos.length; i++) {
        final info = fileInfos[i];
        items.add(CachedMediaItem(
          sourceId: 'music_audio_cache',
          sourcePath: info.file.path,
          mediaType: MediaType.music,
          fileName: appL10n.musicAudioCacheItemName(i + 1, info.extension),
          fileSize: info.stat.size,
          cachePath: info.file.path,
          cachedAt: info.stat.modified,
          lastAccessed: info.stat.accessed,
        ));
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '获取缓存列表失败，非关键功能');
    }
    return items;
  }

  /// 通过缓存路径删除缓存
  Future<void> deleteCacheByPath(String cachePath) async {
    if (!_initialized) await init();

    try {
      final file = File(cachePath);
      if (await file.exists()) {
        await file.delete();
        logger.d('MusicAudioCacheService: 已删除缓存 $cachePath');
      }

      // 同时删除关联文件
      final partFile = File('$cachePath.part');
      if (await partFile.exists()) {
        await partFile.delete();
      }
      final mimeFile = File('$cachePath.mime');
      if (await mimeFile.exists()) {
        await mimeFile.delete();
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '删除缓存失败，非关键功能');
    }
  }
}
