import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/hive_utils.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';

/// 缓存大小配置选项（MB）
class CacheSizeOption {
  const CacheSizeOption(this.sizeMB, this.label);

  /// 大小（MB）
  final int sizeMB;

  /// 显示标签
  final String label;

  /// 转换为字节
  int get sizeBytes => sizeMB * 1024 * 1024;

  /// 预定义选项
  static const List<CacheSizeOption> options = [
    CacheSizeOption(256, '256 MB'),
    CacheSizeOption(512, '512 MB'),
    CacheSizeOption(1024, '1 GB'),
    CacheSizeOption(2048, '2 GB'),
    CacheSizeOption(4096, '4 GB'),
    CacheSizeOption(8192, '8 GB'),
    CacheSizeOption(0, '无限制'),
  ];

  /// 从 MB 值获取选项
  static CacheSizeOption fromMB(int sizeMB) => options.firstWhere(
      (o) => o.sizeMB == sizeMB,
      orElse: () => CacheSizeOption(sizeMB, '$sizeMB MB'),
    );
}

/// 缓存配置服务 - 管理各类型缓存的大小限制
class CacheConfigService {
  factory CacheConfigService() => _instance ??= CacheConfigService._();
  CacheConfigService._();

  static CacheConfigService? _instance;

  bool _initialized = false;

  /// 默认缓存大小配置（MB）
  static const Map<MediaType, int> defaultCacheSizesMB = {
    MediaType.photo: 1024, // 1GB
    MediaType.music: 2048, // 2GB
    MediaType.video: 4096, // 4GB
    MediaType.book: 512, // 512MB
    MediaType.comic: 1024, // 1GB
    MediaType.note: 256, // 256MB
  };

  /// 当前缓存大小配置（MB，0 表示无限制）
  final Map<MediaType, int> _cacheSizesMB = {};

  /// 初始化
  Future<void> init() async {
    if (_initialized) return;

    try {
      final box = await HiveUtils.getSettingsBox();

      // 加载各类型的缓存大小设置
      for (final type in MediaType.values) {
        final key = 'cache_size_${type.name}';
        final savedValue = box.get(key) as int?;
        _cacheSizesMB[type] = savedValue ?? defaultCacheSizesMB[type] ?? 1024;
      }

      _initialized = true;
      logger.i('CacheConfigService: 缓存配置加载完成');
    } catch (e, st) {
      AppError.handle(e, st, 'CacheConfigService.init');
      // 使用默认值
      for (final type in MediaType.values) {
        _cacheSizesMB[type] = defaultCacheSizesMB[type] ?? 1024;
      }
      _initialized = true;
    }
  }

  /// 获取指定类型的缓存大小限制（字节）
  /// 返回 0 表示无限制
  Future<int> getCacheSizeLimit(MediaType type) async {
    if (!_initialized) await init();
    final sizeMB = _cacheSizesMB[type] ?? defaultCacheSizesMB[type] ?? 1024;
    if (sizeMB == 0) return 0; // 无限制
    return sizeMB * 1024 * 1024;
  }

  /// 获取指定类型的缓存大小限制（MB）
  /// 返回 0 表示无限制
  Future<int> getCacheSizeLimitMB(MediaType type) async {
    if (!_initialized) await init();
    return _cacheSizesMB[type] ?? defaultCacheSizesMB[type] ?? 1024;
  }

  /// 设置指定类型的缓存大小限制（MB）
  /// 设置为 0 表示无限制
  Future<void> setCacheSizeLimit(MediaType type, int sizeMB) async {
    if (!_initialized) await init();

    try {
      final box = await HiveUtils.getSettingsBox();
      final key = 'cache_size_${type.name}';
      await box.put(key, sizeMB);
      _cacheSizesMB[type] = sizeMB;

      logger.i('CacheConfigService: 设置 ${type.name} 缓存限制为 $sizeMB MB');
    } catch (e, st) {
      AppError.handle(e, st, 'CacheConfigService.setCacheSizeLimit');
    }
  }

  /// 获取所有类型的缓存配置
  Future<Map<MediaType, int>> getAllCacheSizeLimits() async {
    if (!_initialized) await init();
    return Map.from(_cacheSizesMB);
  }

  /// 重置为默认值
  Future<void> resetToDefaults() async {
    if (!_initialized) await init();

    try {
      final box = await HiveUtils.getSettingsBox();

      for (final type in MediaType.values) {
        final key = 'cache_size_${type.name}';
        await box.delete(key);
        _cacheSizesMB[type] = defaultCacheSizesMB[type] ?? 1024;
      }

      logger.i('CacheConfigService: 已重置为默认缓存配置');
    } catch (e, st) {
      AppError.handle(e, st, 'CacheConfigService.resetToDefaults');
    }
  }

  /// 格式化大小显示
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// 格式化 MB 大小显示
  static String formatSizeMB(int sizeMB) {
    if (sizeMB == 0) return appL10n.cacheConfigServiceUnlimited;
    if (sizeMB < 1024) return '$sizeMB MB';
    return '${(sizeMB / 1024).toStringAsFixed(1)} GB';
  }
}
