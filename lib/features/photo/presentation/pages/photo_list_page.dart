import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/router/app_router.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_glass_app_bar.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/services/media_scan_progress_service.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/photo/data/services/photo_database_service.dart';
import 'package:my_nas/features/photo/data/services/photo_library_cache_service.dart';
import 'package:my_nas/features/photo/domain/entities/photo_item.dart';
import 'package:my_nas/features/photo/presentation/pages/photo_duplicates_page.dart';
import 'package:my_nas/features/photo/presentation/pages/photo_viewer_page.dart';
import 'package:my_nas/features/photo/presentation/widgets/photo_timeline_navigator.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/media_library_page.dart';
import 'package:my_nas/features/sources/presentation/pages/sources_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/transfer/presentation/providers/transfer_provider.dart';
import 'package:my_nas/features/transfer/presentation/widgets/target_picker_sheet.dart';
import 'package:my_nas/features/transfer/presentation/widgets/transfer_sheet.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/local/local_adapter.dart';
import 'package:my_nas/shared/widgets/animated_list_item.dart';
import 'package:my_nas/shared/widgets/context_menu_region.dart';
import 'package:my_nas/shared/widgets/error_widget.dart';
import 'package:my_nas/shared/widgets/stream_image.dart';
import 'package:path_provider/path_provider.dart';

/// 时间线项目类型 - 用于单一 SliverList 渲染
sealed class TimelineItem {
  const TimelineItem();
}

/// 时间线头部项
class TimelineHeader extends TimelineItem {
  const TimelineHeader({
    required this.title,
    required this.count,
  });

  final String title;
  final int count;
}

/// 时间线照片行项
class TimelinePhotoRow extends TimelineItem {
  const TimelinePhotoRow({
    required this.photos,
    required this.globalIndices,
  });

  final List<PhotoFileWithSource> photos;
  final List<int> globalIndices;
}

/// 照片文件及其来源
class PhotoFileWithSource {
  PhotoFileWithSource({
    required this.file,
    required this.sourceId,
  });

  final FileItem file;
  final String sourceId;

  String get name => file.name;
  String get path => file.path;
  int get size => file.size;
  DateTime? get modifiedTime => file.modifiedTime;
  String? get thumbnailUrl => file.thumbnailUrl;

  PhotoLibraryCacheEntry toCacheEntry() => PhotoLibraryCacheEntry(
        sourceId: sourceId,
        filePath: path,
        fileName: name,
        thumbnailUrl: thumbnailUrl,
        size: size,
        modifiedTime: modifiedTime,
      );
}

/// 照片列表状态
final photoListProvider =
    StateNotifierProvider<PhotoListNotifier, PhotoListState>(PhotoListNotifier.new);

/// 照片排序方式
enum PhotoSortType { date, name, size }

/// 照片视图模式
enum PhotoViewMode { grid, timeline }

/// 照片来源筛选
enum PhotoSourceFilter {
  all('全部'),
  local('本机'),
  remote('NAS');

  const PhotoSourceFilter(this.label);
  final String label;
}

/// 判断是否为本机源
bool _isLocalSourceType(SourceType type) => type == SourceType.local;

sealed class PhotoListState {}

class PhotoListLoading extends PhotoListState {
  PhotoListLoading({
    this.progress = 0,
    this.currentFolder,
    this.fromCache = false,
    this.partialPhotos = const [],
    this.scannedCount = 0,
  });
  final double progress;
  final String? currentFolder;
  final bool fromCache;
  final List<PhotoFileWithSource> partialPhotos;
  final int scannedCount;
}

/// 优化后的照片列表状态 - 使用预计算数据
class PhotoListLoaded extends PhotoListState {
  PhotoListLoaded({
    required this.totalCount,
    this.dateGroupCount = 0,
    this.folderCount = 0,
    this.totalSize = 0,
    this.sortType = PhotoSortType.date,
    this.viewMode = PhotoViewMode.grid,
    this.searchQuery = '',
    this.fromCache = false,
    // 时间线筛选
    this.filterYear,
    this.filterMonth,
    // 来源筛选
    this.sourceFilter = PhotoSourceFilter.all,
    // 多选模式
    this.isSelectMode = false,
    this.selectedPaths = const {},
    // 分类数据 - 从 SQLite 预加载
    this.allPhotos = const [],
    this.searchResults = const [],
    this.dateGroups = const [],
    // 用于 O(1) 查找的 Map
    this.photoByPath = const {},
    // 源类型缓存 - 用于快速判断本机/远程
    this.sourceTypeCache = const {},
    // 用于 O(1) 索引查找的 Map
    Map<String, int>? pathToIndex,
    // 缓存的分组数据
    List<PhotoGroup<PhotoEntity>>? cachedGroupedPhotos,
    // 缓存的过滤后照片列表
    List<PhotoFileWithSource>? cachedFilteredPhotos,
  })  : _pathToIndex = pathToIndex,
        _cachedGroupedPhotos = cachedGroupedPhotos,
        _cachedFilteredPhotos = cachedFilteredPhotos;

  final int totalCount;
  final int dateGroupCount;
  final int folderCount;
  final int totalSize;
  final PhotoSortType sortType;
  final PhotoViewMode viewMode;
  final String searchQuery;
  final bool fromCache;

  // 时间线筛选 - 年/月
  final int? filterYear;
  final int? filterMonth;

  // 来源筛选
  final PhotoSourceFilter sourceFilter;

  // 多选模式
  final bool isSelectMode;
  final Set<String> selectedPaths; // 使用 path 作为唯一标识

  // 源类型缓存
  final Map<String, SourceType> sourceTypeCache;

  // 分类数据 - 已从 SQLite 预加载
  final List<PhotoEntity> allPhotos;
  final List<PhotoEntity> searchResults;
  final List<({DateTime date, int count})> dateGroups;

  // 用于 O(1) 查找的 Map
  final Map<String, PhotoEntity> photoByPath;

  // 用于 O(1) 索引查找
  final Map<String, int>? _pathToIndex;

  // 缓存的分组数据 - 避免每次 build 都重新计算
  final List<PhotoGroup<PhotoEntity>>? _cachedGroupedPhotos;

  // 缓存的过滤后照片列表 - 避免每次 build 都重新创建对象
  final List<PhotoFileWithSource>? _cachedFilteredPhotos;

  /// 当前显示的照片（搜索时返回搜索结果，应用时间筛选和来源筛选）
  List<PhotoEntity> get displayPhotos {
    var photos = searchQuery.isNotEmpty ? searchResults : allPhotos;

    // 应用来源筛选
    if (sourceFilter != PhotoSourceFilter.all) {
      photos = photos.where((p) {
        final sourceType = sourceTypeCache[p.sourceId];
        if (sourceType == null) return true; // 未知类型保留
        final isLocal = _isLocalSourceType(sourceType);
        return sourceFilter == PhotoSourceFilter.local ? isLocal : !isLocal;
      }).toList();
    }

    // 应用时间线筛选
    if (filterYear != null) {
      photos = photos.where((p) {
        final date = p.modifiedTime;
        if (date == null) return false;
        if (date.year != filterYear) return false;
        // 如果指定了月份，进一步过滤
        if (filterMonth != null && date.month != filterMonth) return false;
        return true;
      }).toList();
    }

    return photos;
  }

  /// 获取选中的照片列表
  List<PhotoEntity> get selectedPhotos =>
      allPhotos.where((p) => selectedPaths.contains(p.filePath)).toList();

  /// 判断照片是否为本机照片
  bool isLocalPhoto(PhotoEntity photo) {
    final sourceType = sourceTypeCache[photo.sourceId];
    if (sourceType == null) return false;
    return _isLocalSourceType(sourceType);
  }

  /// 获取选中照片中本机照片的数量
  int get selectedLocalCount =>
      selectedPhotos.where(isLocalPhoto).length;

  /// 获取选中照片中远程照片的数量
  int get selectedRemoteCount =>
      selectedPhotos.where((p) => !isLocalPhoto(p)).length;

  /// 兼容旧代码：返回 PhotoFileWithSource 列表
  List<PhotoFileWithSource> get photos => allPhotos
      .map((p) => PhotoFileWithSource(
            file: FileItem(
              name: p.fileName,
              path: p.filePath,
              size: p.size,
              isDirectory: false,
              modifiedTime: p.modifiedTime,
              thumbnailUrl: p.thumbnailUrl,
            ),
            sourceId: p.sourceId,
          ))
      .toList();

  /// 兼容旧代码：过滤后的照片（使用缓存避免重复创建）
  List<PhotoFileWithSource> get filteredPhotos {
    if (_cachedFilteredPhotos != null) return _cachedFilteredPhotos;
    return _computeFilteredPhotos();
  }

  /// 计算过滤后的照片列表（内部方法）
  List<PhotoFileWithSource> _computeFilteredPhotos() => displayPhotos
      .map((p) => PhotoFileWithSource(
            file: FileItem(
              name: p.fileName,
              path: p.filePath,
              size: p.size,
              isDirectory: false,
              modifiedTime: p.modifiedTime,
              thumbnailUrl: p.thumbnailUrl,
            ),
            sourceId: p.sourceId,
          ))
      .toList();

  /// 静态方法：预计算过滤后的照片列表
  static List<PhotoFileWithSource> computeFilteredPhotos(List<PhotoEntity> photos) =>
      photos
          .map((p) => PhotoFileWithSource(
                file: FileItem(
                  name: p.fileName,
                  path: p.filePath,
                  size: p.size,
                  isDirectory: false,
                  modifiedTime: p.modifiedTime,
                  thumbnailUrl: p.thumbnailUrl,
                ),
                sourceId: p.sourceId,
              ))
          .toList();

  /// 通过路径获取照片 - O(1) 查找
  PhotoFileWithSource? getPhotoByPath(String path) {
    final p = photoByPath[path];
    if (p == null) return null;
    return PhotoFileWithSource(
      file: FileItem(
        name: p.fileName,
        path: p.filePath,
        size: p.size,
        isDirectory: false,
        modifiedTime: p.modifiedTime,
        thumbnailUrl: p.thumbnailUrl,
      ),
      sourceId: p.sourceId,
    );
  }

  /// 按日期分组的照片（使用缓存，避免每次 build 都重新计算）
  List<PhotoGroup<PhotoEntity>> get groupedPhotos {
    // 如果有缓存，直接返回
    if (_cachedGroupedPhotos != null) return _cachedGroupedPhotos;
    // 否则计算（仅在首次访问或缓存失效时）
    return _computeGroupedPhotos();
  }

  /// 根据照片数量自动选择分组粒度
  /// - < 1000 张：按天分组
  /// - 1000-5000 张：按月分组
  /// - > 5000 张：按年分组
  PhotoGroupGranularity get autoGranularity {
    final count = displayPhotos.length;
    if (count < 1000) return PhotoGroupGranularity.day;
    if (count < 5000) return PhotoGroupGranularity.month;
    return PhotoGroupGranularity.year;
  }

  /// 根据粒度获取日期键
  static DateTime _getDateKey(PhotoEntity photo, PhotoGroupGranularity granularity) {
    final date = photo.modifiedTime;
    if (date == null || date.year <= 1970) return DateTime(1970);
    return switch (granularity) {
      PhotoGroupGranularity.day => DateTime(date.year, date.month, date.day),
      PhotoGroupGranularity.month => DateTime(date.year, date.month),
      PhotoGroupGranularity.year => DateTime(date.year),
    };
  }

  /// 计算分组数据（内部方法）- 使用自适应粒度
  List<PhotoGroup<PhotoEntity>> _computeGroupedPhotos() {
    final granularity = autoGranularity;
    return _computeGroupedPhotosWithGranularity(displayPhotos, granularity);
  }

  /// 按指定粒度计算分组
  static List<PhotoGroup<PhotoEntity>> _computeGroupedPhotosWithGranularity(
    List<PhotoEntity> photos,
    PhotoGroupGranularity granularity,
  ) {
    final result = <PhotoGroup<PhotoEntity>>[];
    final photosByDate = <DateTime, List<PhotoEntity>>{};

    // 直接使用 PhotoEntity，避免创建新对象
    for (final photo in photos) {
      final dateKey = _getDateKey(photo, granularity);
      photosByDate.putIfAbsent(dateKey, () => []);
      photosByDate[dateKey]!.add(photo);
    }

    // 按日期排序，未知日期放最后
    final sortedDates = photosByDate.keys.toList()
      ..sort((a, b) {
        if (a.year <= 1970) return 1;
        if (b.year <= 1970) return -1;
        return b.compareTo(a);
      });

    for (final date in sortedDates) {
      result.add(PhotoGroup<PhotoEntity>(
        date: date,
        photos: photosByDate[date]!,
        granularity: granularity,
      ));
    }

    return result;
  }

  /// 静态方法：预计算分组数据（用于在状态创建时调用）
  static List<PhotoGroup<PhotoEntity>> computeGroupedPhotos(List<PhotoEntity> photos) {
    // 根据数量自动选择粒度
    final PhotoGroupGranularity granularity;
    if (photos.length < 1000) {
      granularity = PhotoGroupGranularity.day;
    } else if (photos.length < 5000) {
      granularity = PhotoGroupGranularity.month;
    } else {
      granularity = PhotoGroupGranularity.year;
    }
    return _computeGroupedPhotosWithGranularity(photos, granularity);
  }

  /// 计算扁平化的时间线项目列表（用于单一 SliverList 渲染）
  /// 将分组数据转换为：[Header, PhotoRow, PhotoRow, ..., Header, PhotoRow, ...]
  List<TimelineItem> computeTimelineItems(int crossAxisCount) {
    final groups = groupedPhotos;
    final allFilteredPhotos = filteredPhotos;
    final items = <TimelineItem>[];

    for (final group in groups) {
      // 添加头部
      items.add(TimelineHeader(
        title: group.dateTitle,
        count: group.photos.length,
      ));

      // 将组内照片按行分组
      final groupPhotos = <PhotoFileWithSource>[];
      final groupIndices = <int>[];

      for (final photo in group.photos) {
        final globalIndex = getGlobalIndex(photo.filePath);
        if (globalIndex >= 0 && globalIndex < allFilteredPhotos.length) {
          groupPhotos.add(allFilteredPhotos[globalIndex]);
          groupIndices.add(globalIndex);
        }
      }

      // 按 crossAxisCount 分行
      for (var i = 0; i < groupPhotos.length; i += crossAxisCount) {
        final endIndex = (i + crossAxisCount).clamp(0, groupPhotos.length);
        items.add(TimelinePhotoRow(
          photos: groupPhotos.sublist(i, endIndex),
          globalIndices: groupIndices.sublist(i, endIndex),
        ));
      }
    }

    return items;
  }

  /// 获取路径到索引的 Map（惰性构建）
  Map<String, int> get pathToIndex {
    if (_pathToIndex != null) return _pathToIndex;
    // 如果没有预构建，则动态构建
    final map = <String, int>{};
    final photos = displayPhotos;
    for (var i = 0; i < photos.length; i++) {
      map[photos[i].filePath] = i;
    }
    return map;
  }

  /// 获取全局索引 - O(1) 查找
  int getGlobalIndex(String path) => pathToIndex[path] ?? -1;

  PhotoListLoaded copyWith({
    int? totalCount,
    int? dateGroupCount,
    int? folderCount,
    int? totalSize,
    PhotoSortType? sortType,
    PhotoViewMode? viewMode,
    String? searchQuery,
    bool? fromCache,
    // 时间线筛选
    int? filterYear,
    int? filterMonth,
    bool clearFilter = false, // 用于清除筛选
    // 来源筛选
    PhotoSourceFilter? sourceFilter,
    // 多选模式
    bool? isSelectMode,
    Set<String>? selectedPaths,
    List<PhotoEntity>? allPhotos,
    List<PhotoEntity>? searchResults,
    List<({DateTime date, int count})>? dateGroups,
    Map<String, PhotoEntity>? photoByPath,
    Map<String, SourceType>? sourceTypeCache,
    Map<String, int>? pathToIndex,
    List<PhotoGroup<PhotoEntity>>? cachedGroupedPhotos,
    List<PhotoFileWithSource>? cachedFilteredPhotos,
  }) {
    // 如果照片列表、搜索结果或筛选条件变化，需要重建索引和所有缓存
    final needsRebuild = allPhotos != null || searchResults != null || searchQuery != null ||
        filterYear != null || filterMonth != null || sourceFilter != null || clearFilter;
    return PhotoListLoaded(
      totalCount: totalCount ?? this.totalCount,
      dateGroupCount: dateGroupCount ?? this.dateGroupCount,
      folderCount: folderCount ?? this.folderCount,
      totalSize: totalSize ?? this.totalSize,
      sortType: sortType ?? this.sortType,
      viewMode: viewMode ?? this.viewMode,
      searchQuery: searchQuery ?? this.searchQuery,
      fromCache: fromCache ?? this.fromCache,
      filterYear: clearFilter ? null : (filterYear ?? this.filterYear),
      filterMonth: clearFilter ? null : (filterMonth ?? this.filterMonth),
      sourceFilter: sourceFilter ?? this.sourceFilter,
      isSelectMode: isSelectMode ?? this.isSelectMode,
      selectedPaths: selectedPaths ?? this.selectedPaths,
      allPhotos: allPhotos ?? this.allPhotos,
      searchResults: searchResults ?? this.searchResults,
      dateGroups: dateGroups ?? this.dateGroups,
      photoByPath: photoByPath ?? this.photoByPath,
      sourceTypeCache: sourceTypeCache ?? this.sourceTypeCache,
      pathToIndex: needsRebuild ? null : (pathToIndex ?? _pathToIndex),
      // 如果数据变化，清除所有缓存，让其惰性重新计算
      cachedGroupedPhotos: needsRebuild ? null : (cachedGroupedPhotos ?? _cachedGroupedPhotos),
      cachedFilteredPhotos: needsRebuild ? null : (cachedFilteredPhotos ?? _cachedFilteredPhotos),
    );
  }
}

class PhotoListError extends PhotoListState {
  PhotoListError(this.message);
  final String message;
}

class PhotoListNotConnected extends PhotoListState {}

class PhotoListNotifier extends StateNotifier<PhotoListState> {
  PhotoListNotifier(this._ref) : super(PhotoListLoading()) {
    // 使用 addPostFrameCallback 推迟初始化，确保导航动画不被阻塞
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _init();
    });
  }

  final Ref _ref;
  final PhotoLibraryCacheService _cacheService = PhotoLibraryCacheService();
  final PhotoDatabaseService _db = PhotoDatabaseService();
  Timer? _debounceTimer;

  /// 延迟刷新，避免频繁触发
  void _scheduleRefresh() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      logger.i('PhotoListNotifier: 媒体库配置变化，刷新照片列表');
      _loadFromSqlite();
    });
  }

  void _init() {
    logger.d('PhotoListNotifier: 开始初始化...');

    // 关键优化：立即显示空状态UI，让用户立即看到界面
    state = PhotoListLoaded(totalCount: 0);

    // 在后台初始化服务并加载数据，不阻塞UI
    AppError.fireAndForget(_initAndLoadInBackground(), action: 'photoList.initAndLoadInBackground');
  }

  /// 后台初始化服务并加载数据
  Future<void> _initAndLoadInBackground() async {
    try {
      // 并行初始化服务（使用较短超时保护）
      await Future.wait([
        _db.init(),
        _cacheService.init(),
      ]).timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          logger.w('PhotoListNotifier: 服务初始化超时');
          return <void>[];
        },
      );

      logger.d('PhotoListNotifier: 服务初始化完成');

      await _loadFromSqlite();

      // 监听连接状态变化
      _ref.listen<Map<String, SourceConnection>>(activeConnectionsProvider, (previous, next) {
        final prevConnected = previous?.values.where((c) => c.status == SourceStatus.connected).length ?? 0;
        final nextConnected = next.values.where((c) => c.status == SourceStatus.connected).length;

        if (nextConnected > prevConnected && state is PhotoListNotConnected) {
          loadPhotos();
        }
      });

      // 监听媒体库配置变化（启用/停用/移除路径）
      _ref.listen<AsyncValue<MediaLibraryConfig>>(mediaLibraryConfigProvider, (previous, next) {
        final prevPaths = previous?.valueOrNull?.getEnabledPathsForType(MediaType.photo) ?? [];
        final nextPaths = next.valueOrNull?.getEnabledPathsForType(MediaType.photo) ?? [];

        // 比较路径是否变化（包括 sourceId 和 path）
        final prevKeys = prevPaths.map((p) => '${p.sourceId}|${p.path}').toSet();
        final nextKeys = nextPaths.map((p) => '${p.sourceId}|${p.path}').toSet();

        if (prevKeys.length != nextKeys.length || !prevKeys.containsAll(nextKeys)) {
          _scheduleRefresh();
        }
      });
    } on Exception catch (e) {
      logger.e('PhotoListNotifier: 初始化失败', e);
      // 保持空列表状态，让用户可以正常使用界面
    }
  }

  /// 从 SQLite 加载数据
  Future<void> _loadFromSqlite() async {
    final count = await _db.getCount();
    if (count == 0) {
      // SQLite 为空，尝试从旧缓存迁移
      await _migrateFromOldCache();
      return;
    }

    state = PhotoListLoading(fromCache: true, currentFolder: '加载数据...');

    // 并行加载统计和数据
    final results = await Future.wait([
      _db.getStats(),
      _db.getAll(),
      _db.getDateGroups(),
    ]);

    final stats = results[0] as Map<String, dynamic>;
    final allPhotos = results[1] as List<PhotoEntity>;
    final dateGroups = results[2] as List<({DateTime date, int count})>;

    // 构建快速查找 Map
    final photoByPath = <String, PhotoEntity>{};
    for (final p in allPhotos) {
      photoByPath[p.uniqueKey] = p;
    }

    // 预构建路径到索引的 Map，避免惰性构建的首次访问开销
    final pathToIndex = <String, int>{};
    for (var i = 0; i < allPhotos.length; i++) {
      pathToIndex[allPhotos[i].filePath] = i;
    }

    // 构建源类型缓存
    final connections = _ref.read(activeConnectionsProvider);
    final sourceTypeCache = <String, SourceType>{};
    for (final entry in connections.entries) {
      sourceTypeCache[entry.key] = entry.value.source.type;
    }

    // 预计算分组数据
    final cachedGroupedPhotos = PhotoListLoaded.computeGroupedPhotos(allPhotos);

    // 预计算过滤后的照片列表
    final cachedFilteredPhotos = PhotoListLoaded.computeFilteredPhotos(allPhotos);

    // 保留之前的筛选状态
    final current = state;
    final previousFilter = current is PhotoListLoaded ? current.sourceFilter : PhotoSourceFilter.all;

    state = PhotoListLoaded(
      totalCount: stats['total'] as int? ?? 0,
      dateGroupCount: stats['dateGroups'] as int? ?? 0,
      folderCount: stats['folders'] as int? ?? 0,
      totalSize: stats['totalSize'] as int? ?? 0,
      allPhotos: allPhotos,
      dateGroups: dateGroups,
      photoByPath: photoByPath,
      sourceTypeCache: sourceTypeCache,
      pathToIndex: pathToIndex,
      cachedGroupedPhotos: cachedGroupedPhotos,
      cachedFilteredPhotos: cachedFilteredPhotos,
      fromCache: true,
      sourceFilter: previousFilter,
    );

    logger.i('PhotoListNotifier: 从 SQLite 加载了 ${allPhotos.length} 张照片');
  }

  /// 从旧缓存迁移到 SQLite
  Future<void> _migrateFromOldCache() async {
    final cache = _cacheService.getCache();
    if (cache == null || cache.photos.isEmpty) {
      state = PhotoListLoaded(totalCount: 0, fromCache: true);
      return;
    }

    logger.i('PhotoListNotifier: 开始从 Hive 迁移 ${cache.photos.length} 张照片');
    state = PhotoListLoading(currentFolder: '正在迁移数据...', fromCache: true);

    final entities = cache.photos
        .map((entry) => PhotoEntity(
              sourceId: entry.sourceId,
              filePath: entry.filePath,
              fileName: entry.fileName,
              thumbnailUrl: entry.thumbnailUrl,
              size: entry.size,
              modifiedTime: entry.modifiedTime,
              lastUpdated: DateTime.now(),
            ))
        .toList();

    await _db.upsertBatch(entities);
    logger.i('PhotoListNotifier: 迁移完成');

    // 重新加载
    await _loadFromSqlite();
  }

  /// 加载照片库
  ///
  /// 注意：无深度限制，会递归扫描所有子目录
  Future<void> loadPhotos({bool forceRefresh = false}) async {
    final connections = _ref.read(activeConnectionsProvider);
    final configAsync = _ref.read(mediaLibraryConfigProvider);

    var config = configAsync.valueOrNull;
    if (config == null) {
      state = PhotoListLoading(currentFolder: '正在加载配置...');

      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final updated = _ref.read(mediaLibraryConfigProvider);
        config = updated.valueOrNull;
        if (config != null) break;

        if (updated.hasError) {
          state = PhotoListError('加载媒体库配置失败');
          return;
        }
      }

      if (config == null) {
        state = PhotoListLoaded(totalCount: 0);
        return;
      }
    }

    final photoPaths = config.getEnabledPathsForType(MediaType.photo);

    if (photoPaths.isEmpty) {
      state = PhotoListLoaded(totalCount: 0);
      return;
    }

    final connectedPaths = photoPaths.where((path) {
      final conn = connections[path.sourceId];
      return conn?.status == SourceStatus.connected;
    }).toList();

    if (connectedPaths.isEmpty) {
      final current = state;
      if (current is! PhotoListLoaded || current.totalCount == 0) {
        state = PhotoListNotConnected();
      }
      return;
    }

    // 如果不是强制刷新且 SQLite 有数据，直接使用
    if (!forceRefresh) {
      final count = await _db.getCount();
      if (count > 0) {
        await _loadFromSqlite();
        return;
      }
    }

    // 扫描文件系统
    state = PhotoListLoading();
    final photos = <PhotoFileWithSource>[];
    var scannedFolders = 0;
    final totalFolders = connectedPaths.length;
    var lastUpdateCount = 0;

    for (final mediaPath in connectedPaths) {
      final connection = connections[mediaPath.sourceId];
      if (connection == null) continue;

      final fileSystem = connection.adapter.fileSystem;
      state = PhotoListLoading(
        progress: scannedFolders / totalFolders,
        currentFolder: mediaPath.displayName,
        partialPhotos: List.from(photos),
        scannedCount: photos.length,
      );

      try {
        await _scanFolderRecursively(
          fileSystem,
          mediaPath.path,
          photos,
          sourceId: mediaPath.sourceId,
          onBatchFound: () {
            // 每发现 5 个文件更新一次进度，使进度显示更平滑
            if (photos.length - lastUpdateCount >= 5) {
              lastUpdateCount = photos.length;
              state = PhotoListLoading(
                progress: scannedFolders / totalFolders,
                currentFolder: '${mediaPath.displayName} (${photos.length})',
                partialPhotos: List.from(photos),
                scannedCount: photos.length,
              );
            }
          },
        );
      } on Exception catch (e) {
        logger.w('扫描文件夹失败: ${mediaPath.path} - $e');
      }

      scannedFolders++;

      state = PhotoListLoading(
        progress: scannedFolders / totalFolders,
        currentFolder: scannedFolders < totalFolders ? '继续扫描...' : '扫描完成',
        partialPhotos: List.from(photos),
        scannedCount: photos.length,
      );
    }

    logger.i('照片扫描完成，共找到 ${photos.length} 张照片');

    // 保存到 SQLite
    state = PhotoListLoading(
      progress: 1,
      currentFolder: '保存数据...',
      partialPhotos: photos,
      scannedCount: photos.length,
    );

    final entities = photos
        .map((p) => PhotoEntity(
              sourceId: p.sourceId,
              filePath: p.path,
              fileName: p.name,
              thumbnailUrl: p.thumbnailUrl,
              size: p.size,
              modifiedTime: p.modifiedTime,
              lastUpdated: DateTime.now(),
            ))
        .toList();

    await _db.clear(); // 清空旧数据
    await _db.upsertBatch(entities);

    // 重新从 SQLite 加载（确保状态一致）
    await _loadFromSqlite();
  }

  /// 扫描单个目录（用于媒体库页面的单目录扫描）
  ///
  /// 与 loadPhotos 不同，此方法：
  /// 1. 只扫描指定的单个目录
  /// 2. 通过 MediaScanProgressService 发送独立进度
  /// 3. 不改变全局 state（避免影响其他目录的显示）
  Future<int> scanSinglePath({
    required MediaLibraryPath path,
    required Map<String, SourceConnection> connections,
  }) async {
    final progressService = MediaScanProgressService();
    final sourceId = path.sourceId;
    final pathPrefix = path.path;

    final connection = connections[sourceId];
    if (connection == null || connection.status != SourceStatus.connected) {
      logger.w('PhotoListNotifier: 源 $sourceId 未连接，跳过扫描');
      return 0;
    }

    // 标记开始扫描
    progressService.startScan(MediaType.photo, sourceId, pathPrefix);

    try {
      await _db.init();

      // 清理该路径的旧数据（避免旧路径格式的数据残留）
      final deletedCount = await _db.deleteByPath(sourceId, pathPrefix);
      if (deletedCount > 0) {
        logger.i('PhotoListNotifier: 已清理 $sourceId:$pathPrefix 的 $deletedCount 条旧数据');
      }

      // 扫描文件系统
      final photos = <PhotoFileWithSource>[];
      var lastUpdateCount = 0;
      var lastSavedCount = 0;
      const batchSaveSize = 50; // 每 50 张保存一次并刷新 UI

      await _scanFolderRecursivelyWithProgress(
        connection.adapter.fileSystem,
        pathPrefix,
        photos,
        sourceId: sourceId,
        rootPathPrefix: pathPrefix,
        progressService: progressService,
        onBatchFound: () {
          // 更新进度显示
          if (photos.length - lastUpdateCount >= 5) {
            lastUpdateCount = photos.length;
            progressService.emitProgress(MediaScanProgress(
              mediaType: MediaType.photo,
              phase: MediaScanPhase.scanning,
              sourceId: sourceId,
              pathPrefix: pathPrefix,
              scannedCount: photos.length,
              currentPath: '$pathPrefix (${photos.length})',
            ));
          }

          // 边扫边显示：每 batchSaveSize 张保存到数据库并刷新 UI
          if (photos.length - lastSavedCount >= batchSaveSize) {
            final batchPhotos = photos.sublist(lastSavedCount, photos.length);
            lastSavedCount = photos.length;

            final entities = batchPhotos
                .map((p) => PhotoEntity(
                      sourceId: p.sourceId,
                      filePath: p.path,
                      fileName: p.name,
                      thumbnailUrl: p.thumbnailUrl,
                      size: p.size,
                      modifiedTime: p.modifiedTime,
                      lastUpdated: DateTime.now(),
                    ))
                .toList();

            // 异步保存并刷新 UI，不阻塞扫描
            AppError.fireAndForget(
              Future(() async {
                await _db.upsertBatch(entities);
                logger.d('PhotoListNotifier: 边扫边显示 - 保存 ${entities.length} 张照片');
                await _loadFromSqlite();
              }),
              action: 'photoScanBatchSave',
            );
          }
        },
      );

      logger.i('PhotoListNotifier: 目录 $pathPrefix 扫描完成，找到 ${photos.length} 张照片');

      // 保存剩余的照片到数据库
      if (photos.length > lastSavedCount) {
        progressService.emitProgress(MediaScanProgress(
          mediaType: MediaType.photo,
          phase: MediaScanPhase.saving,
          sourceId: sourceId,
          pathPrefix: pathPrefix,
          scannedCount: photos.length,
          totalCount: photos.length,
        ));

        final remainingPhotos = photos.sublist(lastSavedCount);
        final entities = remainingPhotos
            .map((p) => PhotoEntity(
                  sourceId: p.sourceId,
                  filePath: p.path,
                  fileName: p.name,
                  thumbnailUrl: p.thumbnailUrl,
                  size: p.size,
                  modifiedTime: p.modifiedTime,
                  lastUpdated: DateTime.now(),
                ))
            .toList();

        await _db.upsertBatch(entities);
        logger.d('PhotoListNotifier: 保存剩余 ${entities.length} 张照片');
      }

      // 完成扫描
      progressService.endScan(MediaType.photo, sourceId, pathPrefix, success: true);

      // 最终刷新 UI
      await _loadFromSqlite();

      return photos.length;
    } on Exception catch (e) {
      logger.e('PhotoListNotifier: 扫描目录 $pathPrefix 失败', e);
      progressService.endScan(MediaType.photo, sourceId, pathPrefix, success: false);
      rethrow;
    }
  }

  /// 带进度的递归扫描照片文件
  Future<void> _scanFolderRecursivelyWithProgress(
    NasFileSystem fileSystem,
    String path,
    List<PhotoFileWithSource> photos, {
    required String sourceId,
    required String rootPathPrefix,
    required MediaScanProgressService progressService,
    VoidCallback? onBatchFound,
  }) async {
    try {
      // ignore: avoid_print
      print('📷 PhotoScan: 扫描目录 "$path"');
      final files = await fileSystem.listDirectory(path);
      // ignore: avoid_print
      print('📷 PhotoScan: 目录 "$path" 返回 ${files.length} 个文件');

      for (final file in files) {
        // ignore: avoid_print
        print('📷 PhotoScan:   - ${file.name} (isDir=${file.isDirectory}, type=${file.type}, ext=${file.extension})');

        if (file.type == FileType.image) {
          // 优先使用已有的缩略图 URL
          var thumbnailUrl = file.thumbnailUrl;

          // 如果没有缩略图 URL，尝试通过文件系统获取
          // 注意：不调用 getFileUrl() 因为这会触发 I/O 操作（如 asset.file）
          // StreamImage 支持 null thumbnailUrl，会使用 getFileStream 按需加载
          if (thumbnailUrl == null || thumbnailUrl.isEmpty) {
            try {
              thumbnailUrl = await fileSystem.getThumbnailUrl(
                file.path,
                size: ThumbnailSize.medium,
              );
            } on Exception {
              // ignore - thumbnailUrl 保持为 null，StreamImage 会使用流式加载
            }
          }

          final fileWithThumbnail = FileItem(
            name: file.name,
            path: file.path,
            isDirectory: file.isDirectory,
            size: file.size,
            modifiedTime: file.modifiedTime,
            createdTime: file.createdTime,
            mimeType: file.mimeType,
            extension: file.extension,
            thumbnailUrl: thumbnailUrl,
            isHidden: file.isHidden,
            isReadOnly: file.isReadOnly,
          );

          photos.add(PhotoFileWithSource(file: fileWithThumbnail, sourceId: sourceId));
          onBatchFound?.call();
        } else if (file.isDirectory) {
          if (_shouldSkipDirectory(file.name)) {
            continue;
          }

          await _scanFolderRecursivelyWithProgress(
            fileSystem,
            file.path,
            photos,
            sourceId: sourceId,
            rootPathPrefix: rootPathPrefix,
            progressService: progressService,
            onBatchFound: onBatchFound,
          );
        }
      }
    } on Exception catch (e) {
      logger.w('扫描子文件夹失败: $path - $e');
    }
  }

  /// 递归扫描照片文件（无深度限制）
  ///
  /// 会跳过以下目录：
  /// - 隐藏目录（以 . 开头）
  /// - 系统目录（以 @ 开头、#recycle）
  Future<void> _scanFolderRecursively(
    NasFileSystem fileSystem,
    String path,
    List<PhotoFileWithSource> photos, {
    required String sourceId,
    VoidCallback? onBatchFound,
  }) async {
    try {
      final files = await fileSystem.listDirectory(path);

      for (final file in files) {
        if (file.type == FileType.image) {
          // 优先使用已有的缩略图 URL
          var thumbnailUrl = file.thumbnailUrl;

          // 如果没有缩略图 URL，尝试通过文件系统获取
          // 注意：不调用 getFileUrl() 因为这会触发 I/O 操作（如 asset.file）
          // StreamImage 支持 null thumbnailUrl，会使用 getFileStream 按需加载
          if (thumbnailUrl == null || thumbnailUrl.isEmpty) {
            try {
              thumbnailUrl = await fileSystem.getThumbnailUrl(
                file.path,
                size: ThumbnailSize.medium,
              );
            } on Exception {
              // ignore - thumbnailUrl 保持为 null，StreamImage 会使用流式加载
            }
          }

          final fileWithThumbnail = FileItem(
            name: file.name,
            path: file.path,
            isDirectory: file.isDirectory,
            size: file.size,
            modifiedTime: file.modifiedTime,
            createdTime: file.createdTime,
            mimeType: file.mimeType,
            extension: file.extension,
            thumbnailUrl: thumbnailUrl,
            isHidden: file.isHidden,
            isReadOnly: file.isReadOnly,
          );

          photos.add(PhotoFileWithSource(file: fileWithThumbnail, sourceId: sourceId));
          onBatchFound?.call();
        } else if (file.isDirectory) {
          if (_shouldSkipDirectory(file.name)) {
            continue;
          }

          await _scanFolderRecursively(
            fileSystem,
            file.path,
            photos,
            sourceId: sourceId,
            onBatchFound: onBatchFound,
          );
        }
      }
    } on Exception catch (e) {
      logger.w('扫描子文件夹失败: $path - $e');
    }
  }

  /// 判断是否应该跳过该目录
  bool _shouldSkipDirectory(String name) => name.startsWith('.') ||
        name.startsWith('@') ||
        name.startsWith('#recycle');

  void setSearchQuery(String query) {
    final current = state;
    if (current is PhotoListLoaded) {
      if (query.isEmpty) {
        state = current.copyWith(searchQuery: '', searchResults: []);
      } else {
        // 使用 SQLite 搜索
        _db.search(query).then((results) {
          if (state is PhotoListLoaded) {
            state = (state as PhotoListLoaded).copyWith(
              searchQuery: query,
              searchResults: results,
            );
          }
        });
        // 先更新搜索词，结果异步返回
        state = current.copyWith(searchQuery: query);
      }
    }
  }

  void setSortType(PhotoSortType sortType) {
    final current = state;
    if (current is PhotoListLoaded) {
      state = current.copyWith(sortType: sortType);
    }
  }

  void toggleViewMode() {
    final current = state;
    if (current is PhotoListLoaded) {
      final nextMode = current.viewMode == PhotoViewMode.grid
          ? PhotoViewMode.timeline
          : PhotoViewMode.grid;
      state = current.copyWith(viewMode: nextMode);
    }
  }

  /// 设置时间线筛选（年/月）
  void setTimelineFilter({int? year, int? month}) {
    final current = state;
    if (current is PhotoListLoaded) {
      state = current.copyWith(filterYear: year, filterMonth: month);
    }
  }

  /// 清除时间线筛选
  void clearTimelineFilter() {
    final current = state;
    if (current is PhotoListLoaded) {
      state = current.copyWith(clearFilter: true);
    }
  }

  /// 强制刷新
  Future<void> forceRefresh() async {
    await _db.clear();
    await _cacheService.clearCache();
    await loadPhotos(forceRefresh: true);
  }

  /// 从媒体库移除照片（只删除数据库记录，不删除源文件）
  Future<bool> removeFromLibrary(PhotoEntity photo) async {
    try {
      await _db.delete(photo.sourceId, photo.filePath);
      await _loadFromSqlite();
      logger.i('PhotoListNotifier: 已从媒体库移除 ${photo.fileName}');
      return true;
    } on Exception catch (e) {
      logger.e('PhotoListNotifier: 移除照片失败', e);
      return false;
    }
  }

  /// 删除照片源文件（同时删除数据库记录和源文件）
  Future<bool> deleteFromSource(PhotoEntity photo) async {
    try {
      final connections = _ref.read(activeConnectionsProvider);
      final connection = connections[photo.sourceId];
      if (connection == null || connection.status != SourceStatus.connected) {
        logger.w('PhotoListNotifier: 无法删除，源未连接');
        return false;
      }

      await connection.adapter.fileSystem.delete(photo.filePath);
      await _db.delete(photo.sourceId, photo.filePath);
      await _loadFromSqlite();

      logger.i('PhotoListNotifier: 已删除源文件 ${photo.fileName}');
      return true;
    } on Exception catch (e) {
      logger.e('PhotoListNotifier: 删除照片源文件失败', e);
      return false;
    }
  }

  /// 设置来源筛选
  void setSourceFilter(PhotoSourceFilter filter) {
    final current = state;
    if (current is PhotoListLoaded) {
      state = current.copyWith(sourceFilter: filter);
    }
  }

  /// 切换多选模式
  void toggleSelectMode() {
    final current = state;
    if (current is PhotoListLoaded) {
      state = current.copyWith(
        isSelectMode: !current.isSelectMode,
        selectedPaths: {}, // 切换模式时清空选择
      );
    }
  }

  /// 进入多选模式
  void enterSelectMode() {
    final current = state;
    if (current is PhotoListLoaded && !current.isSelectMode) {
      state = current.copyWith(isSelectMode: true);
    }
  }

  /// 退出多选模式
  void exitSelectMode() {
    final current = state;
    if (current is PhotoListLoaded && current.isSelectMode) {
      state = current.copyWith(isSelectMode: false, selectedPaths: {});
    }
  }

  /// 切换照片选择状态
  void togglePhotoSelection(String path) {
    final current = state;
    if (current is PhotoListLoaded) {
      final newSelected = Set<String>.from(current.selectedPaths);
      if (newSelected.contains(path)) {
        newSelected.remove(path);
      } else {
        newSelected.add(path);
      }
      state = current.copyWith(selectedPaths: newSelected);
    }
  }

  /// 选择所有当前显示的照片
  void selectAll() {
    final current = state;
    if (current is PhotoListLoaded) {
      final allPaths = current.displayPhotos.map((p) => p.filePath).toSet();
      state = current.copyWith(selectedPaths: allPaths);
    }
  }

  /// 清空选择
  void clearSelection() {
    final current = state;
    if (current is PhotoListLoaded) {
      state = current.copyWith(selectedPaths: {});
    }
  }
}

class PhotoListPage extends ConsumerStatefulWidget {
  const PhotoListPage({super.key});

  @override
  ConsumerState<PhotoListPage> createState() => _PhotoListPageState();
}

class _PhotoListPageState extends ConsumerState<PhotoListPage> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  bool _showSearch = false;

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 获取问候语
  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) return '夜深了';
    if (hour < 12) return '早上好';
    if (hour < 14) return '中午好';
    if (hour < 18) return '下午好';
    return '晚上好';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(photoListProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uiStyle = ref.watch(uiStyleProvider);
    final safeTop = MediaQuery.of(context).padding.top;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    // iOS 26 Liquid Glass 风格：悬浮布局
    if (uiStyle.isGlass) {
      // 多选模式需要 PhotoListLoaded 状态
      final loadedState = state is PhotoListLoaded ? state : null;
      final isSelectMode = loadedState?.isSelectMode ?? false;

      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0D0D0D) : Colors.grey[50],
        body: Stack(
          children: [
            // 主内容（包含大标题）
            switch (state) {
              PhotoListLoading(
                :final progress,
                :final currentFolder,
                :final fromCache,
                :final partialPhotos,
                :final scannedCount,
              ) =>
                _buildLoadingState(
                  context,
                  progress,
                  currentFolder,
                  fromCache,
                  partialPhotos,
                  scannedCount,
                  isDark,
                ),
              PhotoListNotConnected() => _buildNotConnectedPrompt(context, isDark),
              PhotoListError(:final message) => AppErrorWidget(
                  message: message,
                  onRetry: () => ref.read(photoListProvider.notifier).loadPhotos(),
                ),
              final PhotoListLoaded loaded => loaded.filteredPhotos.isEmpty
                  ? _buildEmptyState(context, ref, isDark)
                  : _buildPhotoContentWithLargeTitle(context, ref, loaded, isDark, safeTop),
            },
            if (_showSearch)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => setState(() => _showSearch = false),
                ),
              ),
            // 悬浮按钮组（右上角）- 多选模式时显示多选头部
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              top: _showSearch ? null : safeTop + 8,
              left: isSelectMode ? 16 : null,
              right: 16,
              bottom: _showSearch
                  ? (keyboardInset > 0 ? keyboardInset + 16 : bottomPadding + 16)
                  : null,
              child: isSelectMode && loadedState != null
                  ? _buildFloatingSelectModeHeader(context, ref, isDark, loadedState)
                  : (_showSearch
                      ? _buildFloatingSearchBar(context, ref, isDark)
                      : _buildFloatingButtons(context, ref, isDark, state)),
            ),
          ],
        ),
      );
    }

    // 经典模式：传统布局
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
      body: Column(
        children: [
          _buildHeader(context, ref, isDark, state),
          Expanded(
            child: switch (state) {
              PhotoListLoading(
                :final progress,
                :final currentFolder,
                :final fromCache,
                :final partialPhotos,
                :final scannedCount,
              ) =>
                _buildLoadingState(
                  context,
                  progress,
                  currentFolder,
                  fromCache,
                  partialPhotos,
                  scannedCount,
                  isDark,
                ),
              PhotoListNotConnected() => _buildNotConnectedPrompt(context, isDark),
              PhotoListError(:final message) => AppErrorWidget(
                  message: message,
                  onRetry: () => ref.read(photoListProvider.notifier).loadPhotos(),
                ),
              final PhotoListLoaded loaded => loaded.filteredPhotos.isEmpty
                  ? _buildEmptyState(context, ref, isDark)
                  : _buildPhotoContent(context, ref, loaded, isDark),
            },
          ),
        ],
      ),
    );
  }

  /// 构建顶部区域
  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    PhotoListState state,
  ) {
    final isSelectMode = state is PhotoListLoaded && state.isSelectMode;
    final uiStyle = ref.watch(uiStyleProvider);

    // 玻璃模式下的染色
    final tintColor = uiStyle.isGlass
        ? (isDark
            ? AppColors.success.withValues(alpha: 0.15)
            : AppColors.success.withValues(alpha: 0.08))
        : null;

    return AdaptiveGlassHeader(
      height: 72,
      backgroundColor: uiStyle.isGlass
          ? tintColor
          : (isDark
              ? const Color(0xFF1A2E1A) // 深绿色调
              : AppColors.success.withValues(alpha: 0.08)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.appBarHorizontalPadding,
          AppSpacing.appBarVerticalPadding,
          AppSpacing.appBarHorizontalPadding,
          AppSpacing.lg,
        ),
        child: switch ((
          _showSearch,
          isSelectMode,
          state,
        )) {
          (true, _, _) => _buildSearchBar(context, ref, isDark),
          (_, true, PhotoListLoaded loadedState) =>
            _buildSelectModeHeader(context, ref, isDark, loadedState),
          _ => _buildGreetingHeader(context, ref, isDark, state),
        },
      ),
    );
  }

  /// 多选模式头部
  Widget _buildSelectModeHeader(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    PhotoListLoaded state,
  ) => Row(
      children: [
        IconButton(
          onPressed: () => ref.read(photoListProvider.notifier).exitSelectMode(),
          icon: Icon(
            Icons.close,
            color: isDark ? Colors.white : Colors.black87,
          ),
          tooltip: '取消',
        ),
        Expanded(
          child: Text(
            state.selectedPaths.isEmpty
                ? '选择照片'
                : '已选择 ${state.selectedPaths.length} 张',
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
        TextButton(
          onPressed: state.selectedPaths.length == state.displayPhotos.length
              ? () => ref.read(photoListProvider.notifier).clearSelection()
              : () => ref.read(photoListProvider.notifier).selectAll(),
          child: Text(
            state.selectedPaths.length == state.displayPhotos.length ? '取消全选' : '全选',
          ),
        ),
      ],
    );

  /// 问候语头部
  Widget _buildGreetingHeader(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    PhotoListState state,
  ) {
    final photoCount = state is PhotoListLoaded ? state.displayPhotos.length : 0;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _getGreeting(),
                style: context.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              if (photoCount > 0)
                Row(
                  children: [
                    Icon(
                      Icons.photo_library_rounded,
                      size: 14,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$photoCount 张照片',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        // 操作按钮 - iOS 26 玻璃风格下使用浮动按钮组
        GlassButtonGroup(
          children: [
            GlassGroupIconButton(
              icon: Icons.search_rounded,
              onPressed: () => setState(() => _showSearch = true),
              tooltip: '搜索',
            ),
            if (state is PhotoListLoaded) ...[
              GlassGroupIconButton(
                icon: Icons.check_circle_outline_rounded,
                onPressed: () => ref.read(photoListProvider.notifier).enterSelectMode(),
                tooltip: '多选',
              ),
              GlassGroupIconButton(
                icon: state.viewMode == PhotoViewMode.grid
                    ? Icons.view_timeline_rounded
                    : Icons.grid_view_rounded,
                onPressed: () => ref.read(photoListProvider.notifier).toggleViewMode(),
                tooltip: state.viewMode == PhotoViewMode.grid ? '时间线' : '网格',
              ),
            ],
            GlassGroupPopupMenuButton<String>(
              icon: Icons.more_vert_rounded,
              tooltip: '更多',
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'duplicates',
                  child: Row(
                    children: const [
                      Icon(Icons.content_copy_rounded, size: 20),
                      SizedBox(width: 12),
                      Text('重复照片'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'library',
                  child: Row(
                    children: const [
                      Icon(Icons.settings_rounded, size: 20),
                      SizedBox(width: 12),
                      Text('媒体库设置'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'sources',
                  child: Row(
                    children: const [
                      Icon(Icons.cloud_rounded, size: 20),
                      SizedBox(width: 12),
                      Text('连接源管理'),
                    ],
                  ),
                ),
              ],
              onSelected: _handlePhotoMenuSelection,
            ),
          ],
        ),
      ],
    );
  }

  /// 搜索栏
  Widget _buildSearchBar(BuildContext context, WidgetRef ref, bool isDark) => Row(
      children: [
        IconButton(
          onPressed: () {
            setState(() => _showSearch = false);
            _searchController.clear();
            ref.read(photoListProvider.notifier).setSearchQuery('');
          },
          icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.black87),
        ),
        Expanded(
          child: TextField(
            controller: _searchController,
            autofocus: true,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: '搜索照片...',
              hintStyle: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[400]),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onChanged: (value) {
              ref.read(photoListProvider.notifier).setSearchQuery(value);
            },
          ),
        ),
        if (_searchController.text.isNotEmpty)
          IconButton(
            onPressed: () {
              _searchController.clear();
              ref.read(photoListProvider.notifier).setSearchQuery('');
            },
            icon: Icon(Icons.close, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
          ),
        if (_searchController.text.isNotEmpty)
          IconButton(
            onPressed: () {
              _searchController.clear();
              ref.read(photoListProvider.notifier).setSearchQuery('');
            },
            icon: Icon(
              Icons.close_rounded,
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
            tooltip: '清除',
          ),
      ],
    );

  /// iOS 26 悬浮按钮组
  Widget _buildFloatingButtons(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    PhotoListState state,
  ) {
    // 获取视图模式（如果已加载）
    final viewMode = state is PhotoListLoaded ? state.viewMode : PhotoViewMode.grid;
    final isLoaded = state is PhotoListLoaded;

    return GlassButtonGroup(
      children: [
        GlassGroupIconButton(
          icon: Icons.search_rounded,
          onPressed: () => setState(() => _showSearch = true),
          tooltip: '搜索',
        ),
        // 多选按钮 - 始终显示，但只有在加载完成后才启用
        GlassGroupIconButton(
          icon: Icons.check_circle_outline_rounded,
          onPressed: isLoaded
              ? () => ref.read(photoListProvider.notifier).enterSelectMode()
              : null,
          tooltip: '多选',
        ),
        // 视图切换按钮 - 始终显示，但只有在加载完成后才启用
        GlassGroupIconButton(
          icon: viewMode == PhotoViewMode.grid
              ? Icons.view_timeline_rounded
              : Icons.grid_view_rounded,
          onPressed: isLoaded
              ? () => ref.read(photoListProvider.notifier).toggleViewMode()
              : null,
          tooltip: viewMode == PhotoViewMode.grid ? '时间线' : '网格',
        ),
        GlassGroupPopupMenuButton<String>(
          icon: Icons.more_vert_rounded,
          tooltip: '更多',
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'duplicates',
              child: Row(
                children: const [
                  Icon(Icons.content_copy_rounded, size: 20),
                  SizedBox(width: 12),
                  Text('重复照片'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'library',
              child: Row(
                children: const [
                  Icon(Icons.settings_rounded, size: 20),
                  SizedBox(width: 12),
                  Text('媒体库设置'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'sources',
              child: Row(
                children: const [
                  Icon(Icons.cloud_rounded, size: 20),
                  SizedBox(width: 12),
                  Text('连接源管理'),
                ],
              ),
            ),
          ],
          onSelected: _handlePhotoMenuSelection,
        ),
      ],
    );
  }

  /// 相册菜单选择处理
  void _handlePhotoMenuSelection(String value) {
    if (!mounted) return;
    switch (value) {
      case 'duplicates':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => const PhotoDuplicatesPage(),
          ),
        );
      case 'library':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => const MediaLibraryPage(),
          ),
        );
      case 'sources':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => const SourcesPage(),
          ),
        );
    }
  }

  /// iOS 26 悬浮搜索栏
  Widget _buildFloatingSearchBar(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final available = screenWidth - 96; // padding + gap + close button
    final searchWidth = available.clamp(220.0, 480.0);

    return GlassFloatingSearchBar(
      controller: _searchController,
      hintText: '搜索照片...',
      width: searchWidth,
      onChanged: (query) {
        ref.read(photoListProvider.notifier).setSearchQuery(query);
      },
      onClose: () {
        setState(() => _showSearch = false);
      },
    );
  }

  /// iOS 26 悬浮多选模式头部
  Widget _buildFloatingSelectModeHeader(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    PhotoListLoaded state,
  ) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.black.withValues(alpha: 0.08),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () => ref.read(photoListProvider.notifier).exitSelectMode(),
                icon: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32),
                tooltip: '取消',
              ),
              const SizedBox(width: 4),
              Text(
                state.selectedPaths.isEmpty
                    ? '选择照片'
                    : '已选择 ${state.selectedPaths.length} 张',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: state.selectedPaths.length == state.displayPhotos.length
                    ? () => ref.read(photoListProvider.notifier).clearSelection()
                    : () => ref.read(photoListProvider.notifier).selectAll(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  state.selectedPaths.length == state.displayPhotos.length ? '取消全选' : '全选',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.success,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// iOS 26 带大标题的照片内容
  Widget _buildPhotoContentWithLargeTitle(
    BuildContext context,
    WidgetRef ref,
    PhotoListLoaded state,
    bool isDark,
    double safeTop,
  ) {
    return Column(
      children: [
        // 时间筛选栏（有筛选时显示，或在时间线模式下显示）- 需要在大标题下方
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.read(photoListProvider.notifier).forceRefresh(),
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                // 顶部安全区域留白
                SliverPadding(padding: EdgeInsets.only(top: safeTop + 8)),
                // 大标题区域（iOS 26 风格）- 右侧留出浮动按钮空间
                _buildLargeTitleSliver(context, state, isDark, hasFloatingButtons: true),
                // 时间筛选栏
                if (state.filterYear != null || state.viewMode == PhotoViewMode.timeline)
                  SliverToBoxAdapter(
                    child: _buildTimelineFilterBar(context, ref, state, isDark),
                  ),
                // 照片内容
                if (state.viewMode == PhotoViewMode.grid)
                  _buildGridView(context, ref, state, isDark)
                else
                  _buildTimelineView(context, ref, state, isDark),
                // 底部留白 - 支持悬浮导航栏
                SliverPadding(padding: EdgeInsets.only(bottom: context.scrollBottomPadding)),
              ],
            ),
          ),
        ),
        // 多选模式底部操作栏
        if (state.isSelectMode && state.selectedPaths.isNotEmpty)
          _buildSelectionActionBar(context, ref, state, isDark),
      ],
    );
  }

  /// iOS 26 大标题 Sliver
  Widget _buildLargeTitleSliver(
    BuildContext context,
    PhotoListLoaded state,
    bool isDark, {
    bool hasFloatingButtons = false,
  }) {
    final photoCount = state.displayPhotos.length;
    final localCount = state.displayPhotos.where(state.isLocalPhoto).length;
    final remoteCount = photoCount - localCount;
    // 右侧留出浮动按钮空间
    final rightPadding = hasFloatingButtons ? 170.0 : 20.0;

    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 8, rightPadding, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 大标题
            Text(
              _getGreeting(),
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            // 统计信息
            if (photoCount > 0)
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _buildStatChip(
                    icon: Icons.photo_library_rounded,
                    label: '$photoCount 照片',
                    color: AppColors.success,
                    isDark: isDark,
                  ),
                  if (localCount > 0)
                    _buildStatChip(
                      icon: Icons.phone_iphone_rounded,
                      label: '$localCount 本机',
                      color: AppColors.primary,
                      isDark: isDark,
                    ),
                  if (remoteCount > 0)
                    _buildStatChip(
                      icon: Icons.cloud_rounded,
                      label: '$remoteCount NAS',
                      color: AppColors.accent,
                      isDark: isDark,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// 统计标签
  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(
    BuildContext context,
    double progress,
    String? currentFolder,
    bool fromCache,
    List<PhotoFileWithSource> partialPhotos,
    int scannedCount,
    bool isDark,
  ) {
    // 如果有部分结果，显示带进度条的网格视图
    if (partialPhotos.isNotEmpty && !fromCache) {
      final width = MediaQuery.of(context).size.width;
      final crossAxisCount = width > 600 ? 5 : 3;

      return Column(
        children: [
          // 扫描进度条
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkBackground : AppColors.lightSurface,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? AppColors.darkOutline : AppColors.lightOutline,
                ),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: progress > 0 ? progress : null,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '正在扫描... 已找到 $scannedCount 张照片',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      if (currentFolder != null)
                        Text(
                          currentFolder,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.grey[500] : Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (progress > 0)
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
              ],
            ),
          ),
          // 部分结果网格
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(4),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: partialPhotos.length,
              itemBuilder: (context, index) {
                final photo = partialPhotos[index];
                final connections = ref.read(activeConnectionsProvider);
                final connection = connections[photo.sourceId];
                final fileSystem = connection?.adapter.fileSystem;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    StreamImage(
                      url: photo.thumbnailUrl,
                      path: photo.path,
                      fileSystem: fileSystem,
                      placeholder: Container(
                        color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                        child: Icon(
                          Icons.photo_rounded,
                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                        ),
                      ),
                      errorWidget: Container(
                        color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                        child: Icon(
                          Icons.photo_rounded,
                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                        ),
                      ),
                      cacheKey: photo.path,
                    ),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      );
    }

    // 没有部分结果时显示加载中心动画
    return Center(
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
            fromCache ? '加载缓存...' : '扫描照片中...',
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
          if (progress > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${(progress * 100).toInt()}%',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
  ) {
    // 获取缓存信息
    final cacheService = PhotoLibraryCacheService();
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
                Icons.photo_library_rounded,
                size: 50,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '照片库为空',
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : null,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '请在媒体库设置中配置照片目录并扫描',
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.grey[400] : Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            // 缓存信息
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

  Widget _buildNotConnectedPrompt(BuildContext context, bool isDark) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '未连接到 NAS',
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkOnSurface : null,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '请先在设置中配置并连接到 NAS 服务器',
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? AppColors.darkOnSurfaceVariant
                    : AppColors.lightOnSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => const SourcesPage()),
                  ),
                  borderRadius: BorderRadius.circular(16),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          '添加连接',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

  Widget _buildPhotoContent(
    BuildContext context,
    WidgetRef ref,
    PhotoListLoaded state,
    bool isDark,
  ) =>
      Column(
        children: [
          // 时间筛选栏（有筛选时显示，或在时间线模式下显示）
          if (state.filterYear != null || state.viewMode == PhotoViewMode.timeline)
            _buildTimelineFilterBar(context, ref, state, isDark),
          // 照片内容
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(photoListProvider.notifier).forceRefresh(),
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  if (state.viewMode == PhotoViewMode.grid)
                    _buildGridView(context, ref, state, isDark)
                  else
                    _buildTimelineView(context, ref, state, isDark),
                  // 底部留白 - 支持悬浮导航栏
                  SliverPadding(padding: EdgeInsets.only(bottom: context.scrollBottomPadding)),
                ],
              ),
            ),
          ),
          // 多选模式底部操作栏
          if (state.isSelectMode && state.selectedPaths.isNotEmpty)
            _buildSelectionActionBar(context, ref, state, isDark),
        ],
      );

  /// 多选模式底部操作栏
  Widget _buildSelectionActionBar(
    BuildContext context,
    WidgetRef ref,
    PhotoListLoaded state,
    bool isDark,
  ) {
    final hasLocalSelected = state.selectedLocalCount > 0;
    final hasRemoteSelected = state.selectedRemoteCount > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // 上传按钮（本机照片可用）
            if (hasLocalSelected)
              _buildActionButton(
                icon: Icons.upload_rounded,
                label: '上传 (${state.selectedLocalCount})',
                onPressed: () => _handleUploadSelected(context, ref, state),
                isDark: isDark,
              ),
            // 下载按钮（远程照片可用）
            if (hasRemoteSelected)
              _buildActionButton(
                icon: Icons.download_rounded,
                label: '下载 (${state.selectedRemoteCount})',
                onPressed: () => _handleDownloadSelected(context, ref, state),
                isDark: isDark,
              ),
            // 删除按钮
            _buildActionButton(
              icon: Icons.delete_outline_rounded,
              label: '删除',
              onPressed: () => _handleDeleteSelected(context, ref, state),
              isDark: isDark,
              isDestructive: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required bool isDark,
    bool isDestructive = false,
  }) {
    final color = isDestructive
        ? AppColors.error
        : (isDark ? Colors.white : AppColors.primary);

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 处理上传选中的照片
  Future<void> _handleUploadSelected(
    BuildContext context,
    WidgetRef ref,
    PhotoListLoaded state,
  ) async {
    // 选择上传目标
    final target = await TargetPickerSheet.show(
      context,
      mediaType: MediaType.photo,
      title: '选择上传目标',
    );

    if (target == null || !context.mounted) return;

    // 获取选中的本机照片
    final localPhotos = state.selectedPhotos.where(state.isLocalPhoto).toList();
    if (localPhotos.isEmpty) return;

    // 添加上传任务
    final notifier = ref.read(transferTasksProvider.notifier);
    var addedCount = 0;

    for (final photo in localPhotos) {
      final task = await notifier.addUploadTask(
        localPath: photo.filePath,
        targetSourceId: target.sourceId,
        targetPath: '${target.path}/${photo.fileName}',
        mediaType: MediaType.photo,
        fileSize: photo.size,
        thumbnailPath: photo.thumbnailUrl,
      );
      if (task != null) addedCount++;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已添加 $addedCount 个上传任务'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: '查看',
            onPressed: () => showTransferUploads(context),
          ),
        ),
      );
      ref.read(photoListProvider.notifier).exitSelectMode();
    }
  }

  /// 处理下载选中的照片
  Future<void> _handleDownloadSelected(
    BuildContext context,
    WidgetRef ref,
    PhotoListLoaded state,
  ) async {
    // 获取选中的远程照片
    final remotePhotos = state.selectedPhotos.where((p) => !state.isLocalPhoto(p)).toList();
    if (remotePhotos.isEmpty) return;

    // 获取下载目录
    final downloadDir = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();

    // 添加下载任务
    final notifier = ref.read(transferTasksProvider.notifier);
    var addedCount = 0;

    for (final photo in remotePhotos) {
      final targetPath = '${downloadDir.path}/${photo.fileName}';
      final task = await notifier.addDownloadTask(
        sourceId: photo.sourceId,
        sourcePath: photo.filePath,
        targetPath: targetPath,
        mediaType: MediaType.photo,
        fileSize: photo.size,
        thumbnailPath: photo.thumbnailUrl,
      );
      if (task != null) addedCount++;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已添加 $addedCount 个下载任务'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: '查看',
            onPressed: () => showTransferDownloads(context),
          ),
        ),
      );
      ref.read(photoListProvider.notifier).exitSelectMode();
    }
  }

  /// 处理删除选中的照片
  Future<void> _handleDeleteSelected(
    BuildContext context,
    WidgetRef ref,
    PhotoListLoaded state,
  ) async {
    final confirmed = await showDeleteConfirmDialog(
      context: context,
      title: '删除照片',
      content: '确定要删除选中的 ${state.selectedPaths.length} 张照片吗？\n\n此操作将同时删除源文件，无法恢复。',
    );

    if (!confirmed || !context.mounted) return;

    final notifier = ref.read(photoListProvider.notifier);
    var successCount = 0;

    for (final photo in state.selectedPhotos) {
      final success = await notifier.deleteFromSource(photo);
      if (success) successCount++;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已删除 $successCount 张照片'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      ref.read(photoListProvider.notifier).exitSelectMode();
    }
  }

  /// 构建时间line筛选栏
  Widget _buildTimelineFilterBar(
    BuildContext context,
    WidgetRef ref,
    PhotoListLoaded state,
    bool isDark,
  ) {
    final hasFilter = state.filterYear != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
          ),
        ),
      ),
      child: Row(
        children: [
          // 日历图标
          Icon(
            Icons.calendar_month_rounded,
            size: 20,
            color: hasFilter ? AppColors.primary : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
          ),
          const SizedBox(width: 8),
          // 筛选按钮
          Expanded(
            child: GestureDetector(
              onTap: () => _showTimelineFilterSheet(context, ref, state),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: hasFilter
                      ? AppColors.primary.withValues(alpha: 0.1)
                      : (isDark ? AppColors.darkSurfaceElevated : Colors.grey[100]),
                  borderRadius: BorderRadius.circular(8),
                  border: hasFilter
                      ? Border.all(color: AppColors.primary.withValues(alpha: 0.3))
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hasFilter
                          ? (state.filterMonth != null
                              ? '${state.filterYear}年${state.filterMonth}月'
                              : '${state.filterYear}年')
                          : '按时间筛选',
                      style: TextStyle(
                        color: hasFilter
                            ? AppColors.primary
                            : (isDark ? Colors.white : Colors.black87),
                        fontWeight: hasFilter ? FontWeight.w600 : FontWeight.normal,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: hasFilter
                          ? AppColors.primary
                          : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 清除筛选按钮
          if (hasFilter) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => ref.read(photoListProvider.notifier).clearTimelineFilter(),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurfaceElevated : Colors.grey[100],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          // 照片数量
          Text(
            '${state.displayPhotos.length}张',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 显示时间线筛选底部弹窗
  void _showTimelineFilterSheet(
    BuildContext context,
    WidgetRef ref,
    PhotoListLoaded state,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => TimelineFilterBottomSheet(
        currentYear: state.filterYear,
        currentMonth: state.filterMonth,
        onYearSelected: (year) {
          ref.read(photoListProvider.notifier).setTimelineFilter(year: year);
        },
        onMonthSelected: (year, month) {
          ref.read(photoListProvider.notifier).setTimelineFilter(year: year, month: month);
        },
        onClearFilter: () {
          ref.read(photoListProvider.notifier).clearTimelineFilter();
        },
      ),
    );
  }

  Widget _buildGridView(
    BuildContext context,
    WidgetRef ref,
    PhotoListLoaded state,
    bool isDark,
  ) {
    final photos = state.filteredPhotos;
    final crossAxisCount = context.isDesktop ? 6 : 3;

    return SliverPadding(
      padding: const EdgeInsets.all(4),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final photo = photos[index];
            // 获取对应的 PhotoEntity 用于删除操作
            final key = '${photo.sourceId}:${photo.path}';
            final entity = state.photoByPath[key];

            return AnimatedGridItem(
              index: index,
              delay: const Duration(milliseconds: 20),
              child: _PhotoGridItem(
                photo: photo,
                index: index,
                allPhotos: photos,
                isDark: isDark,
                photoEntity: entity,
                isSelectMode: state.isSelectMode,
                isSelected: state.selectedPaths.contains(photo.path),
              ),
            );
          },
          childCount: photos.length,
        ),
      ),
    );
  }

  /// 构建单一 Sliver 的时间线视图
  /// 使用扁平化的项目列表，将分组头部和照片行合并为单一 SliverList
  /// 大幅减少 Sliver 数量，提升性能
  Widget _buildTimelineView(
    BuildContext context,
    WidgetRef ref,
    PhotoListLoaded state,
    bool isDark,
  ) {
    final crossAxisCount = context.isDesktop ? 6 : 3;
    final allPhotos = state.filteredPhotos;
    final timelineItems = state.computeTimelineItems(crossAxisCount);
    final screenWidth = MediaQuery.of(context).size.width;
    final itemSize = (screenWidth - 8 - (crossAxisCount - 1) * 4) / crossAxisCount;

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = timelineItems[index];
            return switch (item) {
              TimelineHeader(:final title, :final count) => _buildTimelineHeader(
                  context,
                  title,
                  count,
                  isDark,
                ),
              TimelinePhotoRow(:final photos, :final globalIndices) => _buildTimelinePhotoRow(
                  context,
                  photos,
                  globalIndices,
                  allPhotos,
                  itemSize,
                  crossAxisCount,
                  isDark,
                  state.photoByPath,
                  state.isSelectMode,
                  state.selectedPaths,
                ),
            };
          },
          childCount: timelineItems.length,
        ),
      ),
    );
  }

  /// 构建时间线头部
  Widget _buildTimelineHeader(
    BuildContext context,
    String title,
    int count,
    bool isDark,
  ) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.calendar_today_rounded,
                color: AppColors.primary,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkOnSurface : null,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count 张',
              style: context.textTheme.bodySmall?.copyWith(
                color: isDark
                    ? AppColors.darkOnSurfaceVariant
                    : context.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );

  /// 构建时间线照片行
  Widget _buildTimelinePhotoRow(
    BuildContext context,
    List<PhotoFileWithSource> photos,
    List<int> globalIndices,
    List<PhotoFileWithSource> allPhotos,
    double itemSize,
    int crossAxisCount,
    bool isDark,
    Map<String, PhotoEntity> photoByPath,
    bool isSelectMode,
    Set<String> selectedPaths,
  ) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            for (var i = 0; i < photos.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              SizedBox(
                width: itemSize,
                height: itemSize,
                child: _PhotoGridItem(
                  photo: photos[i],
                  index: globalIndices[i],
                  allPhotos: allPhotos,
                  isDark: isDark,
                  photoEntity: photoByPath['${photos[i].sourceId}:${photos[i].path}'],
                  isSelectMode: isSelectMode,
                  isSelected: selectedPaths.contains(photos[i].path),
                ),
              ),
            ],
            // 如果行未满，用空白填充以保持对齐
            if (photos.length < crossAxisCount) ...[
              const SizedBox(width: 4),
              Expanded(child: SizedBox(height: itemSize)),
            ],
          ],
        ),
      );
}

class _PhotoGridItem extends ConsumerWidget {
  const _PhotoGridItem({
    required this.photo,
    required this.index,
    required this.allPhotos,
    required this.isDark,
    required this.photoEntity,
    this.isSelectMode = false,
    this.isSelected = false,
  });

  final PhotoFileWithSource photo;
  final int index;
  final List<PhotoFileWithSource> allPhotos;
  final bool isDark;
  final PhotoEntity? photoEntity;
  final bool isSelectMode;
  final bool isSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 获取文件系统用于流式加载
    final connections = ref.watch(activeConnectionsProvider);
    final connection = connections[photo.sourceId];
    final fileSystem = connection?.adapter.fileSystem;

    // 使用 RepaintBoundary 隔离重绘，避免单个项目变化导致整个列表重绘
    return RepaintBoundary(
      child: Material(
        color: isDark
            ? AppColors.darkSurfaceElevated
            : context.colorScheme.surfaceContainerHighest,
        child: InkWell(
          onTap: () {
            if (isSelectMode) {
              // 选择模式下，点击切换选择状态
              ref.read(photoListProvider.notifier).togglePhotoSelection(photo.path);
            } else {
              debugPrint('PhotoGridItem: onTap called for ${photo.name}');
              _openPhotoViewer(context, ref);
            }
          },
          onLongPress: () {
            if (!isSelectMode) {
              // 长按进入选择模式并选中当前项
              ref.read(photoListProvider.notifier).enterSelectMode();
              ref.read(photoListProvider.notifier).togglePhotoSelection(photo.path);
            }
          },
          onSecondaryTap: () => _showContextMenu(context, ref),
          child: Stack(
            fit: StackFit.expand,
            children: [
              StreamImage(
                url: photo.thumbnailUrl,
                path: photo.path,
                fileSystem: fileSystem,
                placeholder: _buildPlaceholder(),
                errorWidget: _buildPlaceholder(),
                cacheKey: photo.path,
              ),
              // 选中效果
              if (isSelectMode) ...[
                // 半透明遮罩
                if (isSelected)
                  Container(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                // 选择框
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : Colors.black.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(
                            Icons.check,
                            size: 16,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showContextMenu(BuildContext context, WidgetRef ref) async {
    if (photoEntity == null) return;

    final action = await showMediaFileContextMenu(
      context: context,
      fileName: photo.name,
    );

    if (action == null || !context.mounted) return;

    switch (action) {
      case MediaFileAction.removeFromLibrary:
        final confirmed = await showDeleteConfirmDialog(
          context: context,
          title: '从媒体库移除',
          content: '确定要从媒体库移除「${photo.name}」吗？\n\n这只会移除索引记录，源文件不会被删除。',
          confirmText: '移除',
          isDestructive: false,
        );
        if (confirmed && context.mounted) {
          final success = await ref.read(photoListProvider.notifier).removeFromLibrary(photoEntity!);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(success ? '已从媒体库移除' : '移除失败'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      case MediaFileAction.deleteFromSource:
        final confirmed = await showDeleteConfirmDialog(
          context: context,
          title: '删除源文件',
          content: '确定要删除「${photo.name}」的源文件吗？\n\n⚠️ 此操作不可恢复！文件将从 NAS 中永久删除。',
        );
        if (confirmed && context.mounted) {
          final success = await ref.read(photoListProvider.notifier).deleteFromSource(photoEntity!);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(success ? '已删除源文件' : '删除失败，请检查连接状态'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      case MediaFileAction.addToFavorites:
      case MediaFileAction.removeFromFavorites:
      case MediaFileAction.share:
      case MediaFileAction.viewDetails:
      case MediaFileAction.download:
        // 这些菜单项默认 showXxx=false，当前调用点未启用；
        // 进入此分支说明上层启用了 flag 却忘记实现。
        debugPrint('[PhotoList] MediaFileAction.${action.name} 尚未实现');
    }
  }

  Widget _buildPlaceholder() => Center(
      child: Icon(
        Icons.image_outlined,
        size: 32,
        color: AppColors.fileImage.withValues(alpha: 0.5),
      ),
    );

  Future<void> _openPhotoViewer(BuildContext context, WidgetRef ref) async {
    debugPrint('PhotoViewer: _openPhotoViewer called');
    debugPrint('PhotoViewer: photo.sourceId = ${photo.sourceId}');

    final connections = ref.read(activeConnectionsProvider);
    debugPrint('PhotoViewer: connections count = ${connections.length}');
    debugPrint('PhotoViewer: connections keys = ${connections.keys.toList()}');

    final connection = connections[photo.sourceId];
    if (connection == null) {
      debugPrint('PhotoViewer: connection is null for sourceId=${photo.sourceId}');
      return;
    }
    debugPrint('PhotoViewer: connection found');

    // 获取当前点击照片的原图 URL
    String currentUrl;
    try {
      currentUrl = await connection.adapter.fileSystem.getFileUrl(photo.path);
      debugPrint('PhotoViewer: got currentUrl = $currentUrl');
    } on Exception catch (e) {
      debugPrint('PhotoViewer: failed to get url: $e');
      // 如果获取失败，留空，让查看器去获取
      currentUrl = '';
    }

    // 构建照片列表
    // 当前照片使用原图 URL，其他照片 url 留空，懒加载时再获取
    final photoItems = allPhotos.map((p) {
      final isCurrentPhoto = p.path == photo.path;
      return PhotoItem(
        name: p.name,
        path: p.path,
        // 当前照片使用原图 URL，其他照片 url 为空
        url: isCurrentPhoto ? currentUrl : '',
        sourceId: p.sourceId,
        thumbnailUrl: p.thumbnailUrl,
        size: p.size,
        modifiedAt: p.modifiedTime,
      );
    }).toList();
    debugPrint('PhotoViewer: photoItems count = ${photoItems.length}');

    if (!context.mounted) {
      debugPrint('PhotoViewer: context not mounted');
      return;
    }

    // 使用 rootNavigatorKey 确保全屏显示，不受 ShellRoute 影响
    final navigator = rootNavigatorKey.currentState;
    debugPrint('PhotoViewer: rootNavigatorKey.currentState = $navigator');
    if (navigator == null) {
      debugPrint('PhotoViewer: rootNavigatorKey.currentState is null, trying Navigator.of');
      // 尝试使用 Navigator.of 作为后备方案
      if (context.mounted) {
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (ctx) => PhotoViewerPage(
              photos: photoItems,
              initialIndex: index,
              getPhotoUrl: (path, sourceId) async {
                final conn = connections[sourceId];
                if (conn == null) return null;
                try {
                  return await conn.adapter.fileSystem.getFileUrl(path);
                } on Exception catch (e) {
                  debugPrint('PhotoViewer: 获取URL失败 path=$path, error=$e');
                  return null;
                }
              },
              getFileSystem: (sourceId) {
                final conn = connections[sourceId];
                return conn?.adapter.fileSystem;
              },
              getGalleryFileSystem: (sourceId) {
                final conn = connections[sourceId];
                final adapter = conn?.adapter;
                if (adapter is LocalAdapter) {
                  return adapter.galleryFileSystem;
                }
                return null;
              },
            ),
          ),
        );
      }
      return;
    }

    debugPrint('PhotoViewer: pushing route');
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (ctx) => PhotoViewerPage(
          photos: photoItems,
          initialIndex: index,
          getPhotoUrl: (path, sourceId) async {
            final conn = connections[sourceId];
            if (conn == null) {
              return null;
            }
            try {
              return await conn.adapter.fileSystem.getFileUrl(path);
            } on Exception catch (e) {
              debugPrint('PhotoViewer: 获取URL失败 path=$path, error=$e');
              return null;
            }
          },
          getFileSystem: (sourceId) {
            final conn = connections[sourceId];
            return conn?.adapter.fileSystem;
          },
          getGalleryFileSystem: (sourceId) {
            final conn = connections[sourceId];
            final adapter = conn?.adapter;
            if (adapter is LocalAdapter) {
              return adapter.galleryFileSystem;
            }
            return null;
          },
        ),
      ),
    );
    debugPrint('PhotoViewer: route pushed successfully');
  }
}
