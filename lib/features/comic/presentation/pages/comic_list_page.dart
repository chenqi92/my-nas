import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/router/app_router.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/services/media_scan_progress_service.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/comic/data/services/comic_library_cache_service.dart';
import 'package:my_nas/features/comic/presentation/pages/comic_reader_page.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/media_library_page.dart';
import 'package:my_nas/features/sources/presentation/pages/sources_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/providers/download_provider.dart';
import 'package:my_nas/shared/providers/media_favorites_provider.dart';
import 'package:my_nas/shared/services/nas_file_share_service.dart';
import 'package:my_nas/shared/widgets/context_menu_region.dart';
import 'package:my_nas/shared/widgets/error_widget.dart';
import 'package:my_nas/shared/widgets/media_info_sheet.dart';
import 'package:my_nas/shared/widgets/media_setup_widget.dart';
import 'package:my_nas/shared/widgets/stream_image.dart';

/// 漫画类型
enum ComicType {
  folder, // 文件夹形式（包含图片文件）
  cbz,    // CBZ 压缩包
  cbr,    // CBR 压缩包
  cb7,    // CB7 压缩包
}

/// 漫画项目（代表一个漫画文件夹或压缩包）
class ComicItem {
  ComicItem({
    required this.folderPath,
    required this.folderName,
    required this.sourceId,
    this.coverPath,
    this.pageCount = 0,
    this.modifiedTime,
    this.type = ComicType.folder,
    this.fileSize,
  });

  factory ComicItem.fromCacheEntry(ComicLibraryCacheEntry entry) => ComicItem(
      folderPath: entry.folderPath,
      folderName: entry.folderName,
      sourceId: entry.sourceId,
      coverPath: entry.coverPath,
      pageCount: entry.pageCount,
      modifiedTime: entry.modifiedTime,
      type: ComicType.values.firstWhere(
        (t) => t.name == entry.comicType,
        orElse: () => ComicType.folder,
      ),
      fileSize: entry.fileSize,
    );

  final String folderPath;
  final String folderName;
  final String sourceId;
  final String? coverPath;
  final int pageCount;
  final DateTime? modifiedTime;
  final ComicType type;
  final int? fileSize;

  /// 是否是压缩包格式
  bool get isArchive => type != ComicType.folder;

  /// 获取漫画格式图标
  IconData get formatIcon => switch (type) {
    ComicType.folder => Icons.folder_rounded,
    ComicType.cbz => Icons.archive_rounded,
    ComicType.cbr => Icons.archive_rounded,
    ComicType.cb7 => Icons.archive_rounded,
  };

  /// 格式化文件大小
  String get displaySize {
    if (fileSize == null) return '';
    if (fileSize! < 1024) return '$fileSize B';
    if (fileSize! < 1024 * 1024) return '${(fileSize! / 1024).toStringAsFixed(1)} KB';
    if (fileSize! < 1024 * 1024 * 1024) {
      return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize! / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// 从文件扩展名获取漫画类型
  static ComicType? typeFromExtension(String fileName) {
    final ext = fileName.toLowerCase();
    if (ext.endsWith('.cbz') || ext.endsWith('.zip')) return ComicType.cbz;
    if (ext.endsWith('.cbr') || ext.endsWith('.rar')) return ComicType.cbr;
    if (ext.endsWith('.cb7') || ext.endsWith('.7z')) return ComicType.cb7;
    return null;
  }

  ComicLibraryCacheEntry toCacheEntry() => ComicLibraryCacheEntry(
        sourceId: sourceId,
        folderPath: folderPath,
        folderName: folderName,
        coverPath: coverPath,
        pageCount: pageCount,
        modifiedTime: modifiedTime,
        comicType: type.name,
        fileSize: fileSize,
      );
}

/// 漫画列表状态
final comicListProvider =
    StateNotifierProvider<ComicListNotifier, ComicListState>(
        ComicListNotifier.new);

sealed class ComicListState {}

class ComicListLoading extends ComicListState {
  ComicListLoading({this.progress = 0, this.currentFolder, this.fromCache = false, this.scannedCount = 0});
  final double progress;
  final String? currentFolder;
  final bool fromCache;
  final int scannedCount;
}

class ComicListNotConnected extends ComicListState {}

class ComicListLoaded extends ComicListState {
  ComicListLoaded({
    required this.comics,
    this.fromCache = false,
    this.searchQuery = '',
  });
  final List<ComicItem> comics;
  final bool fromCache;
  final String searchQuery;

  List<ComicItem> get filteredComics {
    if (searchQuery.isEmpty) return comics;
    return comics
        .where((c) => c.folderName.toLowerCase().contains(searchQuery.toLowerCase()))
        .toList();
  }

  ComicListLoaded copyWith({
    List<ComicItem>? comics,
    bool? fromCache,
    String? searchQuery,
  }) =>
      ComicListLoaded(
        comics: comics ?? this.comics,
        fromCache: fromCache ?? this.fromCache,
        searchQuery: searchQuery ?? this.searchQuery,
      );
}

class ComicListError extends ComicListState {
  ComicListError(this.message);
  final String message;
}

class ComicListNotifier extends StateNotifier<ComicListState> {
  ComicListNotifier(this._ref) : super(ComicListLoading()) {
    // 使用 addPostFrameCallback 推迟初始化，确保导航动画不被阻塞
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _init();
    });
  }

  final Ref _ref;
  final ComicLibraryCacheService _cacheService = ComicLibraryCacheService();

  /// 防抖计时器，避免频繁刷新
  Timer? _debounceTimer;

  /// 延迟刷新，避免频繁触发
  void _scheduleRefresh() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      logger.i('ComicListNotifier: 媒体库配置变化，刷新漫画列表');
      _loadFromCacheImmediately();
    });
  }

  // 支持的图片格式
  static const _imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'];

  void _init() {
    logger.d('ComicListNotifier: 开始初始化...');

    // 关键优化：立即显示空状态UI，让用户立即看到界面
    state = ComicListLoaded(comics: []);

    // 在后台初始化服务并加载数据，不阻塞UI
    AppError.fireAndForget(
      _initAndLoadInBackground(),
      action: 'initComicList',
    );
  }

  /// 后台初始化服务并加载数据
  Future<void> _initAndLoadInBackground() async {
    try {
      await _cacheService.init().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          logger.w('ComicListNotifier: 服务初始化超时');
        },
      );

      logger.d('ComicListNotifier: 服务初始化完成');

      await _loadFromCacheImmediately();

      _ref.listen<Map<String, SourceConnection>>(activeConnectionsProvider, (previous, next) {
        final prevConnected = previous?.values.where((c) => c.status == SourceStatus.connected).length ?? 0;
        final nextConnected = next.values.where((c) => c.status == SourceStatus.connected).length;

        if (nextConnected > prevConnected && state is ComicListNotConnected) {
          loadComics();
        }
      });

      // 监听媒体库配置变化（启用/停用/移除路径）
      _ref.listen<AsyncValue<MediaLibraryConfig>>(mediaLibraryConfigProvider, (previous, next) {
        final prevPaths =
            previous?.valueOrNull?.getEnabledPathsForType(MediaType.comic) ?? [];
        final nextPaths =
            next.valueOrNull?.getEnabledPathsForType(MediaType.comic) ?? [];

        // 比较路径是否变化（包括 sourceId 和 path）
        final prevKeys = prevPaths.map((p) => '${p.sourceId}|${p.path}').toSet();
        final nextKeys = nextPaths.map((p) => '${p.sourceId}|${p.path}').toSet();

        if (prevKeys.length != nextKeys.length || !prevKeys.containsAll(nextKeys)) {
          _scheduleRefresh();
        }
      });
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'initComicListNotifier');
      // 保持空列表状态，让用户可以正常使用界面
    }
  }

  Future<void> _loadFromCacheImmediately() async {
    final cache = _cacheService.getCache();
    if (cache != null && cache.comics.isNotEmpty) {
      state = ComicListLoading(fromCache: true, currentFolder: '加载缓存...');

      final comics = cache.comics.map(ComicItem.fromCacheEntry).toList();

      state = ComicListLoaded(comics: comics, fromCache: true);
      logger.i('从缓存加载了 ${comics.length} 本漫画');
    } else {
      state = ComicListLoaded(comics: [], fromCache: true);
    }
  }

  Future<void> loadComics({bool forceRefresh = false}) async {
    final connections = _ref.read(activeConnectionsProvider);
    final configAsync = _ref.read(mediaLibraryConfigProvider);

    var config = configAsync.valueOrNull;
    if (config == null) {
      state = ComicListLoading(currentFolder: '正在加载配置...');
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final updated = _ref.read(mediaLibraryConfigProvider);
        config = updated.valueOrNull;
        if (config != null) break;
        if (updated.hasError) {
          state = ComicListError('加载媒体库配置失败');
          return;
        }
      }
      if (config == null) {
        state = ComicListLoaded(comics: []);
        return;
      }
    }

    final comicPaths = config.getEnabledPathsForType(MediaType.comic);
    if (comicPaths.isEmpty) {
      state = ComicListLoaded(comics: []);
      return;
    }

    final connectedPaths = comicPaths.where((path) {
      final conn = connections[path.sourceId];
      return conn?.status == SourceStatus.connected;
    }).toList();

    if (connectedPaths.isEmpty) {
      if (state is! ComicListLoaded || (state as ComicListLoaded).comics.isEmpty) {
        state = ComicListNotConnected();
      }
      return;
    }

    final sourceIds = connectedPaths.map((p) => p.sourceId).toList();

    // 尝试使用缓存
    if (!forceRefresh && _cacheService.isCacheValid(sourceIds)) {
      final cache = _cacheService.getCache();
      if (cache != null) {
        state = ComicListLoading(fromCache: true, currentFolder: '加载缓存...');

        final comics = cache.comics.map(ComicItem.fromCacheEntry).toList();

        state = ComicListLoaded(comics: comics, fromCache: true);
        logger.i('从缓存加载了 ${comics.length} 本漫画');
        return;
      }
    }

    // 扫描文件系统
    state = ComicListLoading();
    final comics = <ComicItem>[];
    var scannedFolders = 0;
    final totalFolders = connectedPaths.length;

    for (final mediaPath in connectedPaths) {
      final connection = connections[mediaPath.sourceId];
      if (connection == null) continue;

      state = ComicListLoading(
        progress: scannedFolders / totalFolders,
        currentFolder: mediaPath.displayName,
      );

      try {
        var lastUpdateCount = comics.length;
        await _scanForComics(
          connection.adapter.fileSystem,
          mediaPath.path,
          comics,
          sourceId: mediaPath.sourceId,
          onBatchFound: () {
            // 每发现 5 本漫画更新一次进度
            if (comics.length - lastUpdateCount >= 5) {
              lastUpdateCount = comics.length;
              state = ComicListLoading(
                progress: scannedFolders / totalFolders,
                currentFolder: '${mediaPath.displayName} (${comics.length})',
                scannedCount: comics.length,
              );
            }
          },
        );
      } on Exception catch (e, st) {
        AppError.ignore(e, st, '扫描漫画文件夹失败: ${mediaPath.path}');
      }

      scannedFolders++;
    }

    logger.i('漫画扫描完成，共找到 ${comics.length} 本漫画');

    // 保存到缓存
    final cacheEntries = comics.map((c) => c.toCacheEntry()).toList();
    await _cacheService.saveCache(ComicLibraryCache(
      comics: cacheEntries,
      lastUpdated: DateTime.now(),
      sourceIds: sourceIds,
    ));

    state = ComicListLoaded(comics: comics);
  }

  /// 扫描单个目录（用于媒体库页面的单目录扫描）
  Future<int> scanSinglePath({
    required MediaLibraryPath path,
    required Map<String, SourceConnection> connections,
  }) async {
    final progressService = MediaScanProgressService();
    final sourceId = path.sourceId;
    final pathPrefix = path.path;

    final connection = connections[sourceId];
    if (connection == null || connection.status != SourceStatus.connected) {
      logger.w('ComicListNotifier: 源 $sourceId 未连接，跳过扫描');
      return 0;
    }

    progressService.startScan(MediaType.comic, sourceId, pathPrefix);

    try {
      // 清理该路径的旧数据（避免旧路径格式的数据残留）
      final deletedCount = await _cacheService.deleteByPath(sourceId, pathPrefix);
      if (deletedCount > 0) {
        logger.i('ComicListNotifier: 已清理 $sourceId:$pathPrefix 的 $deletedCount 条旧数据');
      }

      final comics = <ComicItem>[];
      var lastUpdateCount = 0;

      await _scanForComicsWithProgress(
        connection.adapter.fileSystem,
        pathPrefix,
        comics,
        sourceId: sourceId,
        rootPathPrefix: pathPrefix,
        progressService: progressService,
        onBatchFound: () {
          if (comics.length - lastUpdateCount >= 5) {
            lastUpdateCount = comics.length;
            progressService.emitProgress(MediaScanProgress(
              mediaType: MediaType.comic,
              phase: MediaScanPhase.scanning,
              sourceId: sourceId,
              pathPrefix: pathPrefix,
              scannedCount: comics.length,
              currentPath: '$pathPrefix (${comics.length})',
            ));
          }
        },
      );

      logger.i('ComicListNotifier: 目录 $pathPrefix 扫描完成，找到 ${comics.length} 本漫画');

      // 保存到缓存
      if (comics.isNotEmpty) {
        progressService.emitProgress(MediaScanProgress(
          mediaType: MediaType.comic,
          phase: MediaScanPhase.saving,
          sourceId: sourceId,
          pathPrefix: pathPrefix,
          scannedCount: comics.length,
          totalCount: comics.length,
        ));

        // 更新缓存（合并现有缓存）
        final existingCache = _cacheService.getCache();
        final existingComics = existingCache?.comics
            .where((c) => !(c.sourceId == sourceId && c.folderPath.startsWith(pathPrefix)))
            .toList() ?? [];

        final newCacheEntries = comics.map((c) => c.toCacheEntry()).toList();
        final allSourceIds = {...?existingCache?.sourceIds, sourceId}.toList();

        await _cacheService.saveCache(ComicLibraryCache(
          comics: [...existingComics, ...newCacheEntries],
          lastUpdated: DateTime.now(),
          sourceIds: allSourceIds,
        ));
      }

      progressService.endScan(MediaType.comic, sourceId, pathPrefix, success: true);

      // 重新加载（从缓存）
      final cache = _cacheService.getCache();
      if (cache != null) {
        final allComics = cache.comics.map(ComicItem.fromCacheEntry).toList();
        state = ComicListLoaded(comics: allComics);
      }

      return comics.length;
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'scanSinglePath');
      progressService.endScan(MediaType.comic, sourceId, pathPrefix, success: false);
      rethrow;
    }
  }

  /// 带进度的递归扫描漫画文件
  Future<void> _scanForComicsWithProgress(
    NasFileSystem fs,
    String path,
    List<ComicItem> comics, {
    required String sourceId,
    required String rootPathPrefix,
    required MediaScanProgressService progressService,
    VoidCallback? onBatchFound,
  }) async {
    try {
      final items = await fs.listDirectory(path);

      for (final item in items) {
        if (_shouldSkipDirectory(item.name)) {
          continue;
        }

        if (item.isDirectory) {
          final comicInfo = await _checkIfComicFolder(fs, item.path);
          if (comicInfo != null) {
            comics.add(ComicItem(
              folderPath: item.path,
              folderName: item.name,
              sourceId: sourceId,
              coverPath: comicInfo.coverPath,
              pageCount: comicInfo.pageCount,
              modifiedTime: item.modifiedTime,
            ));
            onBatchFound?.call();
          } else {
            await _scanForComicsWithProgress(
              fs,
              item.path,
              comics,
              sourceId: sourceId,
              rootPathPrefix: rootPathPrefix,
              progressService: progressService,
              onBatchFound: onBatchFound,
            );
          }
        } else {
          final comicType = ComicItem.typeFromExtension(item.name);
          if (comicType != null) {
            final nameWithoutExt = _removeExtension(item.name);
            comics.add(ComicItem(
              folderPath: item.path,
              folderName: nameWithoutExt,
              sourceId: sourceId,
              modifiedTime: item.modifiedTime,
              type: comicType,
              fileSize: item.size,
            ));
            onBatchFound?.call();
          }
        }
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '扫描漫画目录失败: $path');
    }
  }

  /// 递归扫描漫画文件（无深度限制）
  ///
  /// 扫描逻辑：
  /// 1. 如果是文件夹且包含图片 -> 识别为漫画文件夹
  /// 2. 如果是文件夹但不包含图片 -> 递归进入继续扫描
  /// 3. 如果是漫画压缩包（.cbz/.cbr/.zip/.rar） -> 识别为漫画文件
  ///
  /// 会跳过以下目录：
  /// - 隐藏目录（以 . 开头）
  /// - 系统目录（以 @ 开头、#recycle）
  Future<void> _scanForComics(
    NasFileSystem fs,
    String path,
    List<ComicItem> comics, {
    required String sourceId,
    VoidCallback? onBatchFound,
  }) async {
    try {
      final items = await fs.listDirectory(path);

      for (final item in items) {
        if (_shouldSkipDirectory(item.name)) {
          continue;
        }

        if (item.isDirectory) {
          // 检查这个文件夹是否是漫画（包含图片文件）
          final comicInfo = await _checkIfComicFolder(fs, item.path);
          if (comicInfo != null) {
            // 是漫画文件夹
            comics.add(ComicItem(
              folderPath: item.path,
              folderName: item.name,
              sourceId: sourceId,
              coverPath: comicInfo.coverPath,
              pageCount: comicInfo.pageCount,
              modifiedTime: item.modifiedTime,
            ));
            onBatchFound?.call();
          } else {
            // 不是漫画文件夹，递归进入继续扫描
            await _scanForComics(
              fs,
              item.path,
              comics,
              sourceId: sourceId,
              onBatchFound: onBatchFound,
            );
          }
        } else {
          // 检查是否是漫画压缩包
          final comicType = ComicItem.typeFromExtension(item.name);
          if (comicType != null) {
            // 去掉扩展名作为漫画名称
            final nameWithoutExt = _removeExtension(item.name);
            comics.add(ComicItem(
              folderPath: item.path,
              folderName: nameWithoutExt,
              sourceId: sourceId,
              modifiedTime: item.modifiedTime,
              type: comicType,
              fileSize: item.size,
            ));
            onBatchFound?.call();
          }
        }
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '扫描漫画目录失败（预期错误，无需上报）: $path');
    }
  }

  /// 判断是否应该跳过该目录
  bool _shouldSkipDirectory(String name) => name.startsWith('.') ||
        name.startsWith('@') ||
        name.startsWith('#recycle');

  /// 移除文件扩展名
  String _removeExtension(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot > 0) {
      return fileName.substring(0, lastDot);
    }
    return fileName;
  }

  Future<({String? coverPath, int pageCount})?> _checkIfComicFolder(
    NasFileSystem fs,
    String folderPath,
  ) async {
    try {
      final items = await fs.listDirectory(folderPath);
      final imageFiles = items.where((item) {
        if (item.isDirectory) return false;
        final ext = item.name.toLowerCase();
        return _imageExtensions.any(ext.endsWith);
      }).toList();

      if (imageFiles.isEmpty) return null;

      // 按名称排序，取第一张作为封面
      imageFiles.sort((a, b) => a.name.compareTo(b.name));

      return (
        coverPath: imageFiles.first.path,
        pageCount: imageFiles.length,
      );
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '检查漫画目录失败（预期错误，无需上报）: $folderPath');
      return null;
    }
  }

  void setSearchQuery(String query) {
    final current = state;
    if (current is ComicListLoaded) {
      state = current.copyWith(searchQuery: query);
    }
  }

  Future<void> forceRefresh() async {
    await _cacheService.clearCache();
    await loadComics(forceRefresh: true);
  }

  /// 从媒体库移除（只删除缓存数据）
  Future<bool> removeFromLibrary(
    String sourceId,
    String folderPath,
    String displayTitle,
  ) async {
    try {
      // 从缓存中移除
      final cache = _cacheService.getCache();
      if (cache != null) {
        final updatedComics = cache.comics
            .where((c) => !(c.sourceId == sourceId && c.folderPath == folderPath))
            .toList();
        await _cacheService.saveCache(ComicLibraryCache(
          comics: updatedComics,
          lastUpdated: cache.lastUpdated,
          sourceIds: cache.sourceIds,
        ));
      }

      // 更新状态
      final current = state;
      if (current is ComicListLoaded) {
        final updatedComics = current.comics
            .where((c) => !(c.sourceId == sourceId && c.folderPath == folderPath))
            .toList();
        state = current.copyWith(comics: updatedComics);
      }

      logger.i('从媒体库移除漫画: $displayTitle');
      return true;
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'removeComicFromLibrary', {'title': displayTitle});
      return false;
    }
  }

  /// 从源删除（同时删除源文件）
  Future<bool> deleteFromSource(
    String sourceId,
    String folderPath,
    String displayTitle,
  ) async {
    try {
      // 获取连接
      final connections = _ref.read(activeConnectionsProvider);
      final connection = connections[sourceId];
      if (connection == null) {
        logger.e('删除漫画失败: 连接不存在 - $sourceId');
        return false;
      }

      // 删除源文件/文件夹
      final fs = connection.adapter.fileSystem;
      await fs.delete(folderPath);

      // 从缓存中移除
      final cache = _cacheService.getCache();
      if (cache != null) {
        final updatedComics = cache.comics
            .where((c) => !(c.sourceId == sourceId && c.folderPath == folderPath))
            .toList();
        await _cacheService.saveCache(ComicLibraryCache(
          comics: updatedComics,
          lastUpdated: cache.lastUpdated,
          sourceIds: cache.sourceIds,
        ));
      }

      // 更新状态
      final current = state;
      if (current is ComicListLoaded) {
        final updatedComics = current.comics
            .where((c) => !(c.sourceId == sourceId && c.folderPath == folderPath))
            .toList();
        state = current.copyWith(comics: updatedComics);
      }

      logger.i('删除漫画源文件: $displayTitle');
      return true;
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'deleteComicFromSource', {'title': displayTitle});
      return false;
    }
  }
}

/// 漫画列表内容（供 ReadingPage 使用）
class ComicListContent extends ConsumerStatefulWidget {
  const ComicListContent({super.key});

  @override
  ConsumerState<ComicListContent> createState() => _ComicListContentState();
}

class _ComicListContentState extends ConsumerState<ComicListContent> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(comicListProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return switch (state) {
      ComicListLoading(:final progress, :final currentFolder, :final fromCache) =>
        _buildLoadingState(progress, currentFolder, fromCache, isDark),
      ComicListNotConnected() => const MediaSetupWidget(
          mediaType: MediaType.comic,
          icon: Icons.collections_bookmark_outlined,
        ),
      ComicListError(:final message) => AppErrorWidget(
          message: message,
          onRetry: () => ref.read(comicListProvider.notifier).loadComics(),
        ),
      ComicListLoaded(:final filteredComics) when filteredComics.isEmpty =>
        _buildEmptyState(context, ref, isDark),
      final ComicListLoaded loaded => _buildComicGrid(context, loaded, isDark),
    };
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref, bool isDark) {
    final cacheService = ComicLibraryCacheService();
    final cacheInfo = cacheService.getCacheInfo();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.collections_bookmark_rounded,
                size: 50,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '漫画库为空',
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : null,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '请在媒体库设置中配置漫画目录并扫描',
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.grey[400] : Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.storage_rounded,
                    size: 14,
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    cacheInfo,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const MediaLibraryPage()),
              ),
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('媒体库设置'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const SourcesPage()),
              ),
              icon: const Icon(Icons.cloud_rounded),
              label: const Text('连接管理'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(
    double progress,
    String? currentFolder,
    bool fromCache,
    bool isDark,
  ) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              value: progress > 0 ? progress : null,
              strokeWidth: 4,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            fromCache ? '加载缓存...' : '扫描漫画中...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : null,
            ),
          ),
          if (currentFolder != null) ...[
            const SizedBox(height: 8),
            Text(
              currentFolder,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey[400] : Colors.grey,
              ),
            ),
          ],
        ],
      ),
    );

  Widget _buildComicGrid(BuildContext context, ComicListLoaded state, bool isDark) => RefreshIndicator(
      onRefresh: () => ref.read(comicListProvider.notifier).forceRefresh(),
      child: GridView.builder(
        // 使用动态底部 padding 支持悬浮导航栏
        padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, context.scrollBottomPadding),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.65,
        ),
        itemCount: state.filteredComics.length,
        itemBuilder: (context, index) {
          final comic = state.filteredComics[index];
          return _ComicCard(comic: comic, isDark: isDark);
        },
      ),
    );
}

class _ComicCard extends ConsumerWidget {
  const _ComicCard({required this.comic, required this.isDark});

  final ComicItem comic;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Material(
      color: Colors.transparent,
      child: GestureDetector(
        onLongPress: () => _showContextMenu(context, ref),
        onSecondaryTap: () => _showContextMenu(context, ref),
        child: InkWell(
          onTap: () => _openComic(context, ref),
          borderRadius: BorderRadius.circular(12),
          child: DecoratedBox(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurfaceVariant : Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? AppColors.darkOutline.withValues(alpha: 0.2)
                  : Colors.grey[300]!,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 封面
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: ColoredBox(
                    color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                    child: comic.coverPath != null
                        ? _buildCover(ref)
                        : _buildPlaceholder(),
                  ),
                ),
              ),
              // 标题和信息
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      comic.folderName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark ? AppColors.darkOnSurface : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // 格式图标
                        Icon(
                          comic.formatIcon,
                          size: 12,
                          color: isDark ? AppColors.darkOnSurfaceVariant : Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            comic.isArchive
                                ? comic.displaySize.isNotEmpty
                                    ? comic.displaySize
                                    : comic.type.name.toUpperCase()
                                : '${comic.pageCount} 页',
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? AppColors.darkOnSurfaceVariant : Colors.grey[600],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );

  Widget _buildCover(WidgetRef ref) {
    // 获取当前漫画对应的连接
    final connections = ref.watch(activeConnectionsProvider);
    final conn = connections[comic.sourceId];
    if (conn == null) return _buildPlaceholder();

    // 使用 StreamImage 流式加载封面，支持 SMB/WebDAV
    return StreamImage(
      path: comic.coverPath,
      fileSystem: conn.adapter.fileSystem,
      placeholder: _buildPlaceholder(),
      errorWidget: _buildPlaceholder(),
      cacheKey: '${comic.sourceId}_${comic.coverPath}',
    );
  }

  Widget _buildPlaceholder() => Center(
      child: Icon(
        Icons.collections_bookmark_outlined,
        size: 40,
        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
      ),
    );

  void _openComic(BuildContext context, WidgetRef ref) {
    // 使用 rootNavigatorKey 确保阅读器全屏显示，不显示底部导航栏
    Navigator.of(rootNavigatorKey.currentContext!).push(
      MaterialPageRoute<void>(
        builder: (_) => ComicReaderPage(comic: comic),
      ),
    );
  }

  Future<void> _showContextMenu(BuildContext context, WidgetRef ref) async {
    final favService = ref.read(mediaFavoritesServiceProvider);
    await favService.init();
    final isFav = favService.isFavoriteSync(
      type: MediaType.comic,
      sourceId: comic.sourceId,
      path: comic.folderPath,
    );

    if (!context.mounted) return;
    // 文件夹形式的漫画无单文件可分享 / 下载，仅压缩包格式才显示对应入口
    final action = await showMediaFileContextMenu(
      context: context,
      fileName: comic.folderName,
      showShare: comic.isArchive,
      showAddToFavorites: true,
      isFavorite: isFav,
      showViewDetails: true,
      showDownload: comic.isArchive,
    );

    if (action == null || !context.mounted) return;

    switch (action) {
      case MediaFileAction.removeFromLibrary:
        final confirmed = await showDeleteConfirmDialog(
          context: context,
          title: '从媒体库移除',
          content: '确定要将"${comic.folderName}"从媒体库中移除吗？这只会删除缓存数据，不会影响源文件。',
          confirmText: '移除',
          isDestructive: false,
        );
        if (confirmed && context.mounted) {
          await ref.read(comicListProvider.notifier).removeFromLibrary(
                comic.sourceId,
                comic.folderPath,
                comic.folderName,
              );
        }
      case MediaFileAction.deleteFromSource:
        final confirmed = await showDeleteConfirmDialog(
          context: context,
          title: '删除源文件',
          content: '确定要删除"${comic.folderName}"吗？此操作将同时删除源文件，无法恢复！',
        );
        if (confirmed && context.mounted) {
          await ref.read(comicListProvider.notifier).deleteFromSource(
                comic.sourceId,
                comic.folderPath,
                comic.folderName,
              );
        }
      case MediaFileAction.share:
        await _shareComic(context, ref);
      case MediaFileAction.addToFavorites:
      case MediaFileAction.removeFromFavorites:
        await ref.read(mediaFavoritesActionsProvider).toggle(
              type: MediaType.comic,
              sourceId: comic.sourceId,
              path: comic.folderPath,
              displayName: comic.folderName,
            );
      case MediaFileAction.viewDetails:
        await MediaInfoSheet.show(
          context: context,
          title: comic.folderName,
          subtitle: '漫画 · ${comic.type.name.toUpperCase()}',
          entries: [
            MediaInfoEntry(
              label: '页数',
              value: comic.pageCount > 0 ? '${comic.pageCount} 页' : '',
            ),
            MediaInfoEntry(label: '文件大小', value: comic.displaySize),
            MediaInfoEntry(
              label: '修改时间',
              value: comic.modifiedTime?.toLocal().toString() ?? '',
            ),
            MediaInfoEntry(label: '来源 ID', value: comic.sourceId, copyable: true),
            MediaInfoEntry(label: '路径', value: comic.folderPath, copyable: true),
          ],
        );
      case MediaFileAction.download:
        await _downloadComic(context, ref);
    }
  }

  /// 分享漫画文件（仅 cbz / cbr / cb7 等压缩包格式）
  Future<void> _shareComic(BuildContext context, WidgetRef ref) async {
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[comic.sourceId];
    if (connection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未连接到对应源，请先建立连接')),
      );
      return;
    }
    if (!NasFileShareService.canShare) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前平台不支持系统分享')),
      );
      return;
    }
    final result = await NasFileShareService.shareFromStream(
      fileSystem: connection.adapter.fileSystem,
      path: comic.folderPath,
      fileName: comic.folderName,
    );
    if (!context.mounted) return;
    if (result.isFailure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享失败：${result.error ?? "未知原因"}')),
      );
    }
  }

  /// 漫画压缩包加入下载队列
  Future<void> _downloadComic(BuildContext context, WidgetRef ref) async {
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[comic.sourceId];
    if (connection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未连接到对应源，请先建立连接')),
      );
      return;
    }
    try {
      final url =
          await connection.adapter.fileSystem.getFileUrl(comic.folderPath);
      final service = ref.read(downloadServiceProvider);
      final task = await service.addTask(
        url: url,
        fileName: comic.folderName,
      );
      unawaited(service.startDownload(task.id));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已加入下载：${comic.folderName}')),
      );
    } on Exception catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加入下载失败：$e')),
      );
    }
  }
}
