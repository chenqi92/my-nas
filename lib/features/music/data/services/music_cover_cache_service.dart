import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 音乐封面缓存服务 - 将封面存储在磁盘而非内存
class MusicCoverCacheService {
  factory MusicCoverCacheService() => _instance ??= MusicCoverCacheService._();
  MusicCoverCacheService._();

  static MusicCoverCacheService? _instance;

  String? _cacheDir;
  bool _initialized = false;

  /// 单个封面最大大小（5MB）
  static const int maxCoverSize = 5 * 1024 * 1024;

  /// 缓存目录最大总大小（500MB）
  static const int maxTotalCacheSize = 500 * 1024 * 1024;

  /// 初始化缓存目录
  Future<void> init() async {
    if (_initialized) return;

    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      _cacheDir = p.join(documentsDir.path, 'music_covers');

      final dir = Directory(_cacheDir!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      _initialized = true;
      logger.i('MusicCoverCacheService: 缓存目录初始化完成 $_cacheDir');
    } catch (e, st) {
      AppError.handle(e, st, 'initMusicCoverCache');
      rethrow;
    }
  }

  /// 获取封面缓存路径
  String _getCoverPath(String uniqueKey) {
    // 使用 MD5 哈希生成文件名，避免特殊字符问题
    final hash = md5.convert(utf8.encode(uniqueKey)).toString();
    return p.join(_cacheDir!, '$hash.jpg');
  }

  /// 保存封面到磁盘
  Future<String?> saveCover(String uniqueKey, Uint8List coverData) async {
    if (!_initialized) await init();
    if (coverData.isEmpty) return null;

    // 检查单个封面大小限制
    if (coverData.length > maxCoverSize) {
      logger.w(
        'MusicCoverCacheService: 封面大小超过限制 '
        '${(coverData.length / 1024 / 1024).toStringAsFixed(2)}MB > '
        '${maxCoverSize ~/ 1024 ~/ 1024}MB',
      );
      return null;
    }

    try {
      // 检查缓存总大小，如果超过限制则清理旧文件
      await _ensureCacheQuota(coverData.length);

      final path = _getCoverPath(uniqueKey);
      final file = File(path);
      await file.writeAsBytes(coverData);
      return path;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, appL10n.musicCoverCacheSaveFailed);
      return null;
    }
  }

  /// 确保缓存不超过配额，必要时清理最旧的文件
  Future<void> _ensureCacheQuota(int newFileSize) async {
    final currentSize = await getCacheSize();
    if (currentSize + newFileSize <= maxTotalCacheSize) return;

    try {
      final dir = Directory(_cacheDir!);
      if (!await dir.exists()) return;

      // 获取所有缓存文件及其修改时间
      final files = <MapEntry<File, DateTime>>[];
      await for (final entity in dir.list()) {
        if (entity is File) {
          final stat = await entity.stat();
          files.add(MapEntry(entity, stat.modified));
        }
      }

      // 按修改时间排序（最旧的在前）
      files.sort((a, b) => a.value.compareTo(b.value));

      // 删除最旧的文件直到有足够空间
      var freedSize = 0;
      final targetFreeSize = (currentSize + newFileSize) - maxTotalCacheSize;
      for (final entry in files) {
        if (freedSize >= targetFreeSize) break;

        try {
          final fileSize = await entry.key.length();
          await entry.key.delete();
          freedSize += fileSize;
          logger.d('MusicCoverCacheService: 清理旧封面 ${entry.key.path}');
        } on Exception catch (e, st) {
          AppError.ignore(e, st, appL10n.musicCoverCacheDeleteFileFailed);
        }
      }

      if (freedSize > 0) {
        logger.i(
          'MusicCoverCacheService: 已清理 '
          '${(freedSize / 1024 / 1024).toStringAsFixed(2)}MB 缓存空间',
        );
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, appL10n.musicCoverCacheQuotaFailed);
    }
  }

  /// 保存 Base64 编码的封面到磁盘
  Future<String?> saveCoverFromBase64(String uniqueKey, String base64Data) async {
    if (!_initialized) await init();
    if (base64Data.isEmpty) return null;

    try {
      final data = base64Decode(base64Data);
      return saveCover(uniqueKey, Uint8List.fromList(data));
    } on Exception catch (e, st) {
      AppError.ignore(e, st, appL10n.musicCoverCacheBase64DecodeFailed);
      return null;
    }
  }

  /// 获取封面数据
  Future<Uint8List?> getCover(String uniqueKey) async {
    if (!_initialized) await init();

    try {
      final path = _getCoverPath(uniqueKey);
      final file = File(path);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, appL10n.musicCoverCacheReadFailed);
    }
    return null;
  }

  /// 检查封面是否存在
  Future<bool> hasCover(String uniqueKey) async {
    if (!_initialized) await init();

    final path = _getCoverPath(uniqueKey);
    return File(path).exists();
  }

  /// 获取封面文件路径（如果存在）
  Future<String?> getCoverPath(String uniqueKey) async {
    if (!_initialized) await init();

    final path = _getCoverPath(uniqueKey);
    if (await File(path).exists()) {
      return path;
    }
    return null;
  }

  /// 获取缓存的封面路径（同步方法，动态检查文件存在性）
  /// 仿照影视模块的 getCachedPosterPath 实现
  /// 这个方法可以在沙盒目录 UUID 变化后仍然正确找到缓存文件
  String? getCachedCoverPathSync(String uniqueKey) {
    if (!_initialized || _cacheDir == null) return null;
    final path = _getCoverPath(uniqueKey);
    if (File(path).existsSync()) {
      return path;
    }
    return null;
  }

  /// 获取缓存的封面 URL (file:// 格式)
  /// 如果封面文件存在，返回 file:// URL
  String? getCachedCoverUrl(String uniqueKey) {
    final path = getCachedCoverPathSync(uniqueKey);
    if (path != null) {
      return Uri.file(path).toString();
    }
    return null;
  }

  /// 删除封面
  Future<void> deleteCover(String uniqueKey) async {
    if (!_initialized) await init();

    try {
      final path = _getCoverPath(uniqueKey);
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, appL10n.musicCoverCacheDeleteFailed);
    }
  }

  /// 清空所有封面缓存
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
      logger.i('MusicCoverCacheService: 已清空所有封面缓存');
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'clearAllMusicCoverCache');
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
      AppError.ignore(e, st, appL10n.musicCoverCacheSizeCalculationFailed);
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

  /// 获取缓存目录路径
  String? get cacheDirectory => _cacheDir;
}
