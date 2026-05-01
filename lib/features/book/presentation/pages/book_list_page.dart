import 'dart:async';
import 'dart:io';

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
import 'package:my_nas/features/book/data/services/book_database_service.dart';
import 'package:my_nas/features/book/data/services/book_library_cache_service.dart';
import 'package:my_nas/features/book/data/services/book_metadata_service.dart';
import 'package:my_nas/features/book/data/services/book_preload_service.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:my_nas/features/book/presentation/providers/book_cover_provider.dart';
import 'package:my_nas/features/book/presentation/utils/book_navigator.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/media_library_page.dart';
import 'package:my_nas/features/sources/presentation/pages/sources_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/providers/media_favorites_provider.dart';
import 'package:my_nas/shared/services/nas_file_share_service.dart';
import 'package:my_nas/shared/widgets/context_menu_region.dart';
import 'package:my_nas/shared/widgets/error_widget.dart';
import 'package:my_nas/shared/widgets/media_setup_widget.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// 图书文件及其来源
class BookFileWithSource {
  BookFileWithSource({
    required this.file,
    required this.sourceId,
  });

  final FileItem file;
  final String sourceId;

  String get name => file.name;
  String get path => file.path;
  int get size => file.size;
  DateTime? get modifiedTime => file.modifiedTime;
  String get displaySize => file.displaySize;

  BookLibraryCacheEntry toCacheEntry() => BookLibraryCacheEntry(
        sourceId: sourceId,
        filePath: path,
        fileName: name,
        size: size,
        modifiedTime: modifiedTime,
      );
}

/// 图书列表状态
final bookListProvider =
    StateNotifierProvider<BookListNotifier, BookListState>(
        BookListNotifier.new);

/// 图书排序方式
enum BookSortType { name, date, size, format }

/// 图书来源筛选
enum BookSourceFilter {
  all('全部'),
  local('本机'),
  remote('NAS');

  const BookSourceFilter(this.label);
  final String label;
}

/// 判断是否为本机来源类型
bool _isLocalBookSource(SourceType type) => type == SourceType.local;

/// 阅读内容类别
enum ReadingCategory {
  book('图书', Icons.menu_book_rounded),
  comic('漫画', Icons.collections_rounded),
  note('笔记', Icons.note_alt_rounded),
  online('在线', Icons.cloud_rounded);

  const ReadingCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

sealed class BookListState {}

class BookListLoading extends BookListState {
  BookListLoading({this.progress = 0, this.currentFolder, this.fromCache = false, this.scannedCount = 0});
  final double progress;
  final String? currentFolder;
  final bool fromCache;
  final int scannedCount;
}

class BookListNotConnected extends BookListState {}

/// 优化后的图书列表状态 - 使用预计算数据
class BookListLoaded extends BookListState {
  BookListLoaded({
    required this.totalCount,
    this.totalSize = 0,
    this.formatStats = const {},
    this.sortType = BookSortType.name,
    this.searchQuery = '',
    this.fromCache = false,
    // 分类数据 - 从 SQLite 预加载
    this.allBooks = const [],
    this.searchResults = const [],
    // 用于 O(1) 查找的 Map
    this.bookByPath = const {},
    // 来源筛选和选择模式
    this.sourceFilter = BookSourceFilter.all,
    this.isSelectMode = false,
    this.selectedPaths = const {},
    this.sourceTypeCache = const {},
  });

  final int totalCount;
  final int totalSize;
  final Map<BookFormat, int> formatStats;  // 预计算的格式统计
  final BookSortType sortType;
  final String searchQuery;
  final bool fromCache;

  // 分类数据 - 已从 SQLite 预加载
  final List<BookEntity> allBooks;
  final List<BookEntity> searchResults;

  // 用于 O(1) 查找的 Map
  final Map<String, BookEntity> bookByPath;

  // 来源筛选和选择模式
  final BookSourceFilter sourceFilter;
  final bool isSelectMode;
  final Set<String> selectedPaths; // uniqueKey (sourceId:filePath)
  final Map<String, SourceType> sourceTypeCache; // sourceId -> SourceType

  /// 当前显示的图书（根据筛选条件返回）
  List<BookEntity> get displayBooks {
    final baseList = searchQuery.isNotEmpty ? searchResults : allBooks;
    if (sourceFilter == BookSourceFilter.all) return baseList;

    return baseList.where((book) {
      final sourceType = sourceTypeCache[book.sourceId];
      if (sourceType == null) return sourceFilter == BookSourceFilter.remote;
      final isLocal = _isLocalBookSource(sourceType);
      return sourceFilter == BookSourceFilter.local ? isLocal : !isLocal;
    }).toList();
  }

  /// 判断图书是否为本机图书
  bool isLocalBook(BookEntity book) {
    final sourceType = sourceTypeCache[book.sourceId];
    if (sourceType == null) return false;
    return _isLocalBookSource(sourceType);
  }

  /// 已选中的图书列表
  List<BookEntity> get selectedBooks =>
      allBooks.where((b) => selectedPaths.contains(b.uniqueKey)).toList();

  /// 选中的本机图书数量
  int get selectedLocalCount =>
      selectedBooks.where(isLocalBook).length;

  /// 选中的远程图书数量
  int get selectedRemoteCount =>
      selectedBooks.where((b) => !isLocalBook(b)).length;

  /// 兼容旧代码：返回 BookFileWithSource 列表
  List<BookFileWithSource> get books => allBooks
      .map((b) => BookFileWithSource(
            file: FileItem(
              name: b.fileName,
              path: b.filePath,
              size: b.size,
              isDirectory: false,
              modifiedTime: b.modifiedTime,
            ),
            sourceId: b.sourceId,
          ))
      .toList();

  /// 兼容旧代码：过滤后的图书
  List<BookFileWithSource> get filteredBooks => displayBooks
      .map((b) => BookFileWithSource(
            file: FileItem(
              name: b.fileName,
              path: b.filePath,
              size: b.size,
              isDirectory: false,
              modifiedTime: b.modifiedTime,
            ),
            sourceId: b.sourceId,
          ))
      .toList();

  /// 通过路径获取图书 - O(1) 查找
  BookFileWithSource? getBookByPath(String path) {
    final b = bookByPath[path];
    if (b == null) return null;
    return BookFileWithSource(
      file: FileItem(
        name: b.fileName,
        path: b.filePath,
        size: b.size,
        isDirectory: false,
        modifiedTime: b.modifiedTime,
      ),
      sourceId: b.sourceId,
    );
  }

  BookListLoaded copyWith({
    int? totalCount,
    int? totalSize,
    Map<BookFormat, int>? formatStats,
    BookSortType? sortType,
    String? searchQuery,
    bool? fromCache,
    List<BookEntity>? allBooks,
    List<BookEntity>? searchResults,
    Map<String, BookEntity>? bookByPath,
    BookSourceFilter? sourceFilter,
    bool? isSelectMode,
    Set<String>? selectedPaths,
    Map<String, SourceType>? sourceTypeCache,
  }) =>
      BookListLoaded(
        totalCount: totalCount ?? this.totalCount,
        totalSize: totalSize ?? this.totalSize,
        formatStats: formatStats ?? this.formatStats,
        sortType: sortType ?? this.sortType,
        searchQuery: searchQuery ?? this.searchQuery,
        fromCache: fromCache ?? this.fromCache,
        allBooks: allBooks ?? this.allBooks,
        searchResults: searchResults ?? this.searchResults,
        bookByPath: bookByPath ?? this.bookByPath,
        sourceFilter: sourceFilter ?? this.sourceFilter,
        isSelectMode: isSelectMode ?? this.isSelectMode,
        selectedPaths: selectedPaths ?? this.selectedPaths,
        sourceTypeCache: sourceTypeCache ?? this.sourceTypeCache,
      );
}

class BookListError extends BookListState {
  BookListError(this.message);
  final String message;
}

class BookListNotifier extends StateNotifier<BookListState> {
  BookListNotifier(this._ref) : super(BookListLoading()) {
    // 使用 addPostFrameCallback 推迟初始化，确保导航动画不被阻塞
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _init();
    });
  }

  final Ref _ref;
  final BookLibraryCacheService _cacheService = BookLibraryCacheService();
  final BookDatabaseService _db = BookDatabaseService();
  final BookPreloadService _preloadService = BookPreloadService();
  final BookMetadataService _metadataService = BookMetadataService();

  /// 后台元数据提取是否正在运行
  bool _isExtractingMetadata = false;

  /// 防抖计时器，避免频繁刷新
  Timer? _debounceTimer;

  /// 延迟刷新，避免频繁触发
  void _scheduleRefresh() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      logger.i('BookListNotifier: 媒体库配置变化，刷新图书列表');
      _loadFromSqlite();
    });
  }

  /// 支持的电子书扩展名
  static const _supportedExtensions = [
    '.epub',
    '.pdf',
    '.txt',
    '.mobi',
    '.azw3',
  ];

  void _init() {
    logger.d('BookListNotifier: 开始初始化...');

    // 关键优化：立即显示空状态UI，让用户立即看到界面
    state = BookListLoaded(totalCount: 0);

    // 在后台初始化服务并加载数据，不阻塞UI
    AppError.fireAndForget(
      _initAndLoadInBackground(),
      action: 'BookListNotifier.initAndLoadInBackground',
    );
  }

  /// 后台初始化服务并加载数据
  Future<void> _initAndLoadInBackground() async {
    try {
      // 并行初始化服务（使用较短超时保护）
      await Future.wait([
        _db.init(),
        _cacheService.init(),
        _preloadService.init(),
      ]).timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          logger.w('BookListNotifier: 服务初始化超时');
          return <void>[];
        },
      );

      logger.d('BookListNotifier: 服务初始化完成');

      await _loadFromSqlite();

      // 监听连接状态变化
      _ref..listen<Map<String, SourceConnection>>(activeConnectionsProvider, (previous, next) {
        final prevConnected = previous?.values.where((c) => c.status == SourceStatus.connected).length ?? 0;
        final nextConnected = next.values.where((c) => c.status == SourceStatus.connected).length;

        if (nextConnected > prevConnected && state is BookListNotConnected) {
          loadBooks();
        }
      })

      // 监听媒体库配置变化（启用/停用/移除路径）
      ..listen<AsyncValue<MediaLibraryConfig>>(mediaLibraryConfigProvider, (previous, next) {
        final prevPaths =
            previous?.valueOrNull?.getEnabledPathsForType(MediaType.book) ?? [];
        final nextPaths =
            next.valueOrNull?.getEnabledPathsForType(MediaType.book) ?? [];

        // 比较路径是否变化（包括 sourceId 和 path）
        final prevKeys = prevPaths.map((p) => '${p.sourceId}|${p.path}').toSet();
        final nextKeys = nextPaths.map((p) => '${p.sourceId}|${p.path}').toSet();

        if (prevKeys.length != nextKeys.length || !prevKeys.containsAll(nextKeys)) {
          _scheduleRefresh();
        }
      });
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'BookListNotifier.initAndLoad');
      // 恢复到空列表状态，避免一直 loading
      state = BookListLoaded(totalCount: 0);
    }
  }

  /// 从 SQLite 加载数据
  Future<void> _loadFromSqlite() async {
    try {
      final count = await _db.getCount();
      if (count == 0) {
        // SQLite 为空，尝试从旧缓存迁移
        await _migrateFromOldCache();
        return;
      }

      state = BookListLoading(fromCache: true, currentFolder: '加载数据...');

      // 并行加载统计和数据
      final results = await Future.wait([
        _db.getStats(),
        _db.getAll(),
      ]);

      final stats = results[0] as Map<String, dynamic>;
      final allBooks = results[1] as List<BookEntity>;

      // 转换格式统计
      final rawFormatStats = stats['formatStats'] as Map<String, int>? ?? {};
      final formatStats = <BookFormat, int>{};
      for (final entry in rawFormatStats.entries) {
        final format = BookFormat.values.firstWhere(
          (f) => f.name == entry.key,
          orElse: () => BookFormat.unknown,
        );
        formatStats[format] = entry.value;
      }

      // 构建快速查找 Map
      final bookByPath = <String, BookEntity>{};
      for (final b in allBooks) {
        bookByPath[b.uniqueKey] = b;
      }

      // 构建来源类型缓存
      final connections = _ref.read(activeConnectionsProvider);
      final sourceTypeCache = <String, SourceType>{};
      for (final book in allBooks) {
        if (!sourceTypeCache.containsKey(book.sourceId)) {
          final conn = connections[book.sourceId];
          if (conn != null) {
            sourceTypeCache[book.sourceId] = conn.source.type;
          }
        }
      }

      state = BookListLoaded(
        totalCount: stats['total'] as int? ?? 0,
        totalSize: stats['totalSize'] as int? ?? 0,
        formatStats: formatStats,
        allBooks: allBooks,
        bookByPath: bookByPath,
        sourceTypeCache: sourceTypeCache,
        fromCache: true,
      );

      logger.i('BookListNotifier: 从 SQLite 加载了 ${allBooks.length} 本图书');

      // 启动后台元数据提取（不阻塞 UI）
      AppError.fireAndForget(
        _extractMetadataInBackground(),
        action: 'BookListNotifier.extractMetadataInBackground',
      );

      // 启动后台预加载（只预加载前 20 本）
      _startPreloading(allBooks.take(20).toList());
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'BookListNotifier.loadFromSqlite');
      // 加载失败时恢复到空状态，避免一直 loading
      state = BookListLoaded(totalCount: 0);
    }
  }

  /// 启动后台预加载
  void _startPreloading(List<BookEntity> books) {
    if (books.isEmpty) return;

    final connections = _ref.read(activeConnectionsProvider);

    _preloadService.enqueue(
      books,
      (sourceId) {
        final conn = connections[sourceId];
        if (conn?.status == SourceStatus.connected) {
          return conn!.adapter.fileSystem;
        }
        return null;
      },
    );
  }

  /// 从旧缓存迁移到 SQLite
  Future<void> _migrateFromOldCache() async {
    final cache = _cacheService.getCache();
    if (cache == null || cache.books.isEmpty) {
      state = BookListLoaded(totalCount: 0, fromCache: true);
      return;
    }

    logger.i('BookListNotifier: 开始从 Hive 迁移 ${cache.books.length} 本图书');
    state = BookListLoading(currentFolder: '正在迁移数据...', fromCache: true);

    final entities = cache.books
        .map((entry) => BookEntity(
              sourceId: entry.sourceId,
              filePath: entry.filePath,
              fileName: entry.fileName,
              format: BookItem.formatFromExtension(entry.fileName),
              size: entry.size,
              modifiedTime: entry.modifiedTime,
              lastUpdated: DateTime.now(),
            ))
        .toList();

    await _db.upsertBatch(entities);
    logger.i('BookListNotifier: 迁移完成');

    // 重新加载
    await _loadFromSqlite();
  }

  /// 加载书籍库
  ///
  /// 注意：无深度限制，会递归扫描所有子目录
  Future<void> loadBooks({bool forceRefresh = false}) async {
    final connections = _ref.read(activeConnectionsProvider);
    final configAsync = _ref.read(mediaLibraryConfigProvider);

    var config = configAsync.valueOrNull;
    if (config == null) {
      state = BookListLoading(currentFolder: '正在加载配置...');

      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final updated = _ref.read(mediaLibraryConfigProvider);
        config = updated.valueOrNull;
        if (config != null) break;

        if (updated.hasError) {
          state = BookListError('加载媒体库配置失败');
          return;
        }
      }

      if (config == null) {
        state = BookListLoaded(totalCount: 0);
        return;
      }
    }

    final bookPaths = config.getEnabledPathsForType(MediaType.book);

    if (bookPaths.isEmpty) {
      state = BookListLoaded(totalCount: 0);
      return;
    }

    final connectedPaths = bookPaths.where((path) {
      final conn = connections[path.sourceId];
      return conn?.status == SourceStatus.connected;
    }).toList();

    if (connectedPaths.isEmpty) {
      final current = state;
      if (current is! BookListLoaded || current.totalCount == 0) {
        state = BookListNotConnected();
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
    state = BookListLoading();
    final books = <BookFileWithSource>[];
    var scannedFolders = 0;
    final totalFolders = connectedPaths.length;

    for (final mediaPath in connectedPaths) {
      final connection = connections[mediaPath.sourceId];
      if (connection == null) continue;

      state = BookListLoading(
        progress: scannedFolders / totalFolders,
        currentFolder: mediaPath.displayName,
      );

      try {
        var lastUpdateCount = books.length;
        await _scanForBooks(
          connection.adapter.fileSystem,
          mediaPath.path,
          books,
          sourceId: mediaPath.sourceId,
          onBatchFound: () {
            // 每发现 5 本书更新一次进度
            if (books.length - lastUpdateCount >= 5) {
              lastUpdateCount = books.length;
              state = BookListLoading(
                progress: scannedFolders / totalFolders,
                currentFolder: '${mediaPath.displayName} (${books.length})',
                scannedCount: books.length,
              );
            }
          },
        );
      } on Exception catch (e) {
        logger.w('扫描书籍文件夹失败: ${mediaPath.path} - $e');
      }

      scannedFolders++;
    }

    logger.i('书籍扫描完成，共找到 ${books.length} 本书');

    // 保存到 SQLite
    state = BookListLoading(
      progress: 1,
      currentFolder: '保存数据...',
    );

    final entities = books
        .map((b) => BookEntity(
              sourceId: b.sourceId,
              filePath: b.path,
              fileName: b.name,
              format: BookItem.formatFromExtension(b.name),
              size: b.size,
              modifiedTime: b.modifiedTime,
              lastUpdated: DateTime.now(),
            ))
        .toList();

    await _db.clear();
    await _db.upsertBatch(entities);

    // 重新从 SQLite 加载（确保状态一致）
    await _loadFromSqlite();
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
      logger.w('BookListNotifier: 源 $sourceId 未连接，跳过扫描');
      return 0;
    }

    progressService.startScan(MediaType.book, sourceId, pathPrefix);

    try {
      await _db.init();

      // 清理该路径的旧数据（避免旧路径格式的数据残留）
      final deletedCount = await _db.deleteByPath(sourceId, pathPrefix);
      if (deletedCount > 0) {
        logger.i('BookListNotifier: 已清理 $sourceId:$pathPrefix 的 $deletedCount 条旧数据');
      }

      final books = <BookFileWithSource>[];
      var lastUpdateCount = 0;
      var lastSavedCount = 0;
      const batchSaveSize = 30; // 每 30 本保存一次并刷新 UI

      await _scanForBooksWithProgress(
        connection.adapter.fileSystem,
        pathPrefix,
        books,
        sourceId: sourceId,
        rootPathPrefix: pathPrefix,
        progressService: progressService,
        onBatchFound: () {
          // 更新进度显示
          if (books.length - lastUpdateCount >= 5) {
            lastUpdateCount = books.length;
            progressService.emitProgress(MediaScanProgress(
              mediaType: MediaType.book,
              phase: MediaScanPhase.scanning,
              sourceId: sourceId,
              pathPrefix: pathPrefix,
              scannedCount: books.length,
              currentPath: '$pathPrefix (${books.length})',
            ));
          }

          // 边扫边显示：每 batchSaveSize 本保存到数据库并刷新 UI
          if (books.length - lastSavedCount >= batchSaveSize) {
            final batchBooks = books.sublist(lastSavedCount, books.length);
            lastSavedCount = books.length;

            final entities = batchBooks
                .map((b) => BookEntity(
                      sourceId: b.sourceId,
                      filePath: b.path,
                      fileName: b.name,
                      format: BookItem.formatFromExtension(b.name),
                      size: b.size,
                      modifiedTime: b.modifiedTime,
                      lastUpdated: DateTime.now(),
                    ))
                .toList();

            // 异步保存并刷新 UI，不阻塞扫描
            AppError.fireAndForget(
              Future(() async {
                await _db.upsertBatch(entities);
                logger.d('BookListNotifier: 边扫边显示 - 保存 ${entities.length} 本书');
                await _loadFromSqlite();
              }),
              action: 'bookScanBatchSave',
            );
          }
        },
      );

      logger.i('BookListNotifier: 目录 $pathPrefix 扫描完成，找到 ${books.length} 本书');

      // 保存剩余的书籍到数据库
      if (books.length > lastSavedCount) {
        progressService.emitProgress(MediaScanProgress(
          mediaType: MediaType.book,
          phase: MediaScanPhase.saving,
          sourceId: sourceId,
          pathPrefix: pathPrefix,
          scannedCount: books.length,
          totalCount: books.length,
        ));

        final remainingBooks = books.sublist(lastSavedCount);
        final entities = remainingBooks
            .map((b) => BookEntity(
                  sourceId: b.sourceId,
                  filePath: b.path,
                  fileName: b.name,
                  format: BookItem.formatFromExtension(b.name),
                  size: b.size,
                  modifiedTime: b.modifiedTime,
                  lastUpdated: DateTime.now(),
                ))
            .toList();

        await _db.upsertBatch(entities);
        logger.d('BookListNotifier: 保存剩余 ${entities.length} 本书');
      }

      progressService.endScan(MediaType.book, sourceId, pathPrefix, success: true);

      // 最终刷新 UI
      await _loadFromSqlite();

      return books.length;
    } on Exception catch (e) {
      logger.e('BookListNotifier: 扫描目录 $pathPrefix 失败', e);
      progressService.endScan(MediaType.book, sourceId, pathPrefix, success: false);
      rethrow;
    }
  }

  /// 带进度的递归扫描书籍文件
  Future<void> _scanForBooksWithProgress(
    NasFileSystem fs,
    String path,
    List<BookFileWithSource> books, {
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
          await _scanForBooksWithProgress(
            fs,
            item.path,
            books,
            sourceId: sourceId,
            rootPathPrefix: rootPathPrefix,
            progressService: progressService,
            onBatchFound: onBatchFound,
          );
        } else if (_isBookFile(item.name)) {
          books.add(BookFileWithSource(file: item, sourceId: sourceId));
          onBatchFound?.call();
        }
      }
    } on Exception catch (e) {
      logger.w('扫描子文件夹失败: $path - $e');
    }
  }

  /// 递归扫描书籍文件（无深度限制）
  ///
  /// 会跳过以下目录：
  /// - 隐藏目录（以 . 开头）
  /// - 系统目录（以 @ 开头、#recycle）
  Future<void> _scanForBooks(
    NasFileSystem fs,
    String path,
    List<BookFileWithSource> books, {
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
          await _scanForBooks(
            fs,
            item.path,
            books,
            sourceId: sourceId,
            onBatchFound: onBatchFound,
          );
        } else if (_isBookFile(item.name)) {
          books.add(BookFileWithSource(file: item, sourceId: sourceId));
          onBatchFound?.call();
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

  bool _isBookFile(String filename) {
    final lower = filename.toLowerCase();
    return _supportedExtensions.any(lower.endsWith);
  }

  void setSearchQuery(String query) {
    final current = state;
    if (current is BookListLoaded) {
      if (query.isEmpty) {
        state = current.copyWith(searchQuery: '', searchResults: []);
      } else {
        // 使用 SQLite 搜索
        _db.search(query).then((results) {
          if (state is BookListLoaded) {
            state = (state as BookListLoaded).copyWith(
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

  void setSortType(BookSortType sortType) {
    final current = state;
    if (current is BookListLoaded) {
      state = current.copyWith(sortType: sortType);
    }
  }

  /// 设置来源筛选
  void setSourceFilter(BookSourceFilter filter) {
    final current = state;
    if (current is BookListLoaded) {
      state = current.copyWith(
        sourceFilter: filter,
        // 切换筛选时清空选择
        isSelectMode: false,
        selectedPaths: {},
      );
    }
  }

  /// 切换选择模式
  void toggleSelectMode() {
    final current = state;
    if (current is BookListLoaded) {
      state = current.copyWith(
        isSelectMode: !current.isSelectMode,
        selectedPaths: {},
      );
    }
  }

  /// 进入选择模式（从长按触发）
  void enterSelectMode(String bookKey) {
    final current = state;
    if (current is BookListLoaded && !current.isSelectMode) {
      state = current.copyWith(
        isSelectMode: true,
        selectedPaths: {bookKey},
      );
    }
  }

  /// 退出选择模式
  void exitSelectMode() {
    final current = state;
    if (current is BookListLoaded) {
      state = current.copyWith(
        isSelectMode: false,
        selectedPaths: {},
      );
    }
  }

  /// 切换图书选择状态
  void toggleBookSelection(String bookKey) {
    final current = state;
    if (current is BookListLoaded) {
      final newSelected = Set<String>.from(current.selectedPaths);
      if (newSelected.contains(bookKey)) {
        newSelected.remove(bookKey);
      } else {
        newSelected.add(bookKey);
      }
      state = current.copyWith(selectedPaths: newSelected);
    }
  }

  /// 全选当前筛选下的图书
  void selectAll() {
    final current = state;
    if (current is BookListLoaded) {
      final allKeys = current.displayBooks.map((b) => b.uniqueKey).toSet();
      state = current.copyWith(selectedPaths: allKeys);
    }
  }

  /// 清空选择
  void clearSelection() {
    final current = state;
    if (current is BookListLoaded) {
      state = current.copyWith(selectedPaths: {});
    }
  }

  /// 强制刷新
  Future<void> forceRefresh() async {
    await _db.clear();
    await _cacheService.clearCache();
    await loadBooks(forceRefresh: true);
  }

  /// 从媒体库移除图书（只删除数据库记录，不删除源文件）
  Future<bool> removeFromLibrary(String sourceId, String filePath, String displayTitle) async {
    try {
      await _db.delete(sourceId, filePath);
      await _loadFromSqlite();
      logger.i('BookListNotifier: 已从媒体库移除 $displayTitle');
      return true;
    } on Exception catch (e) {
      logger.e('BookListNotifier: 移除图书失败', e);
      return false;
    }
  }

  /// 删除图书源文件（同时删除数据库记录和源文件）
  Future<bool> deleteFromSource(String sourceId, String filePath, String displayTitle) async {
    try {
      final connections = _ref.read(activeConnectionsProvider);
      final connection = connections[sourceId];
      if (connection == null || connection.status != SourceStatus.connected) {
        logger.w('BookListNotifier: 无法删除，源未连接');
        return false;
      }

      await connection.adapter.fileSystem.delete(filePath);
      await _db.delete(sourceId, filePath);
      await _loadFromSqlite();

      logger.i('BookListNotifier: 已删除源文件 $displayTitle');
      return true;
    } on Exception catch (e) {
      logger.e('BookListNotifier: 删除图书源文件失败', e);
      return false;
    }
  }

  /// 后台提取元数据
  /// 从数据库中查找未提取元数据的图书，逐个提取并更新
  Future<void> _extractMetadataInBackground() async {
    if (_isExtractingMetadata) return;
    _isExtractingMetadata = true;

    try {
      await _metadataService.init();

      final connections = _ref.read(activeConnectionsProvider);

      // 分批获取未提取元数据的图书
      while (mounted) {
        final unextracted = await _db.getUnextractedMetadata(limit: 10);
        if (unextracted.isEmpty) {
          logger.i('BookListNotifier: 元数据提取完成');
          break;
        }

        logger.d('BookListNotifier: 发现 ${unextracted.length} 本书待提取元数据');

        for (final book in unextracted) {
          if (!mounted) break;

          // 获取对应的文件系统
          final connection = connections[book.sourceId];
          if (connection?.status != SourceStatus.connected) {
            // 标记为已处理（避免重复尝试）
            await _db.upsert(book.copyWith(metadataExtracted: true));
            continue;
          }

          final fileSystem = connection!.adapter.fileSystem;

          try {
            // 提取元数据
            final metadata = await _metadataService.extractFromNasFile(
              fileSystem,
              book.filePath,
              book.format,
            );

            if (metadata != null) {
              // 保存封面到本地
              String? coverPath;
              if (metadata.hasCover) {
                coverPath = await _metadataService.saveCoverToCache(
                  book.sourceId,
                  book.filePath,
                  metadata.coverData!,
                );
              }

              // 更新数据库
              final updatedBook = book.copyWith(
                title: metadata.title,
                author: metadata.author,
                description: metadata.description,
                coverPath: coverPath,
                totalPages: metadata.totalPages,
                metadataExtracted: true,
              );

              await _db.upsert(updatedBook);

              // 更新 UI 状态
              _updateBookInState(updatedBook);

              logger.d('BookListNotifier: 提取元数据成功: ${metadata.title ?? book.fileName}');
            } else {
              // 元数据提取失败，标记为已处理
              await _db.upsert(book.copyWith(metadataExtracted: true));
            }
          } on Exception catch (e) {
            logger.w('BookListNotifier: 提取元数据失败: ${book.fileName}', e);
            // 标记为已处理，避免无限重试
            await _db.upsert(book.copyWith(metadataExtracted: true));
          }

          // 添加短暂延迟，避免过于频繁的 IO 操作
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    } on Exception catch (e) {
      logger.e('BookListNotifier: 后台元数据提取出错', e);
    } finally {
      _isExtractingMetadata = false;
    }
  }

  /// 更新状态中的单本图书（用于元数据提取后刷新 UI）
  void _updateBookInState(BookEntity updatedBook) {
    final current = state;
    if (current is BookListLoaded) {
      final updatedBooks = current.allBooks.map((b) {
        if (b.sourceId == updatedBook.sourceId && b.filePath == updatedBook.filePath) {
          return updatedBook;
        }
        return b;
      }).toList();

      final updatedByPath = Map<String, BookEntity>.from(current.bookByPath);
      updatedByPath[updatedBook.uniqueKey] = updatedBook;

      state = current.copyWith(
        allBooks: updatedBooks,
        bookByPath: updatedByPath,
      );
    }
  }
}


/// 缓存信息条
class _BookCacheInfoBar extends ConsumerWidget {
  const _BookCacheInfoBar({
    required this.state,
    required this.isDark,
  });

  final BookListLoaded state;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cacheService = BookLibraryCacheService();
    final cache = cacheService.getCache();

    if (cache == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final bookCount = state.totalCount;
    final formatStats = state.formatStats;
    final cacheAge = DateTime.now().difference(cache.lastUpdated);
    final ageText = cacheAge.inHours < 1
        ? '${cacheAge.inMinutes} 分钟前'
        : cacheAge.inHours < 24
            ? '${cacheAge.inHours} 小时前'
            : '${cacheAge.inDays} 天前';

    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkBackground : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? AppColors.darkOutline : AppColors.lightOutline,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.menu_book_rounded,
              size: 14,
              color: AppColors.fileDocument,
            ),
            const SizedBox(width: 4),
            Text(
              '$bookCount',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              '本图书',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
            const SizedBox(width: 12),
            // 格式统计
            ...formatStats.entries.take(3).map((entry) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getFormatColor(entry.key).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${entry.key.name.toUpperCase()} ${entry.value}',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: _getFormatColor(entry.key),
                      ),
                    ),
                  ),
                )),
            const Spacer(),
            Icon(
              Icons.update_rounded,
              size: 14,
              color: isDark ? Colors.grey[500] : Colors.grey[600],
            ),
            const SizedBox(width: 4),
            Text(
              ageText,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getFormatColor(BookFormat format) => switch (format) {
      BookFormat.epub => const Color(0xFF6366F1),
      BookFormat.pdf => const Color(0xFFEF4444),
      BookFormat.txt => const Color(0xFF6B7280),
      BookFormat.mobi || BookFormat.azw3 => const Color(0xFFF59E0B),
      BookFormat.unknown => const Color(0xFF6B7280),
    };
}

/// 图书列表内容组件（供阅读页面复用）
class BookListContent extends ConsumerStatefulWidget {
  const BookListContent({super.key});

  @override
  ConsumerState<BookListContent> createState() => _BookListContentState();
}

class _BookListContentState extends ConsumerState<BookListContent> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bookListProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return switch (state) {
      BookListLoading(:final progress, :final currentFolder, :final fromCache) =>
        _buildLoadingState(progress, currentFolder, fromCache, isDark),
      BookListNotConnected() => const MediaSetupWidget(
          mediaType: MediaType.book,
          icon: Icons.menu_book_outlined,
        ),
      BookListError(:final message) => AppErrorWidget(
          message: message,
          onRetry: () => ref.read(bookListProvider.notifier).loadBooks(),
        ),
      BookListLoaded(:final displayBooks) when displayBooks.isEmpty =>
        _buildEmptyState(context, isDark),
      final BookListLoaded loaded => _buildBookGrid(context, ref, loaded, isDark),
    };
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    // 获取缓存信息
    final cacheService = BookLibraryCacheService();
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
                Icons.menu_book_rounded,
                size: 50,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '图书库为空',
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : null,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '请在媒体库设置中配置图书目录并扫描\n支持 EPUB、PDF、TXT 格式',
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
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              value: progress > 0 ? progress : null,
              strokeWidth: 3,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            fromCache ? '加载缓存...' : '扫描图书中...',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : null,
            ),
          ),
          if (currentFolder != null) ...[
            const SizedBox(height: 6),
            Text(
              currentFolder,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[400] : Colors.grey,
              ),
            ),
          ],
        ],
      ),
    );

  Widget _buildBookGrid(
    BuildContext context,
    WidgetRef ref,
    BookListLoaded state,
    bool isDark,
  ) => RefreshIndicator(
      onRefresh: () => ref.read(bookListProvider.notifier).forceRefresh(),
      child: GridView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 140,
          childAspectRatio: 0.6,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: state.displayBooks.length,
        itemBuilder: (context, index) {
          final book = state.displayBooks[index];
          return _BookGridItem(
            key: ValueKey('${book.sourceId}_${book.filePath}'),
            bookEntity: book,
            isDark: isDark,
          );
        },
      ),
    );
}

class _BookGridItem extends ConsumerStatefulWidget {
  const _BookGridItem({
    required this.bookEntity,
    required this.isDark,
    this.isSelectMode = false,
    this.isSelected = false,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  final BookEntity bookEntity;
  final bool isDark;
  final bool isSelectMode;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  ConsumerState<_BookGridItem> createState() => _BookGridItemState();
}

class _BookGridItemState extends ConsumerState<_BookGridItem> {
  String? _coverPath;
  bool _coverLoaded = false;
  bool _loadingStarted = false;
  /// 是否已经进入过可视区域（用于懒加载）
  bool _hasBeenVisible = false;

  @override
  void initState() {
    super.initState();
    // 不在 initState 中立即加载封面
    // 等待 VisibilityDetector 检测到可见时再加载
  }

  @override
  void didUpdateWidget(covariant _BookGridItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果书籍变了，重新加载封面
    if (oldWidget.bookEntity.filePath != widget.bookEntity.filePath ||
        oldWidget.bookEntity.sourceId != widget.bookEntity.sourceId) {
      _coverPath = null;
      _coverLoaded = false;
      _loadingStarted = false;
      // 重置可见性标记，如果当前可见会由 VisibilityDetector 重新触发加载
      _hasBeenVisible = false;
    }
  }

  void _loadCoverIfNeeded() {
    if (_loadingStarted || _coverLoaded) return;
    _loadingStarted = true;
    _loadCover();
  }

  Future<void> _loadCover() async {
    final book = widget.bookEntity;
    final format = book.format;

    // 支持封面提取的格式：EPUB、PDF、MOBI、AZW3
    if (format != BookFormat.epub &&
        format != BookFormat.pdf &&
        format != BookFormat.mobi &&
        format != BookFormat.azw3) {
      if (mounted) {
        setState(() => _coverLoaded = true);
      }
      return;
    }

    // 优先使用已缓存的封面路径（从数据库元数据）- 同步检查
    if (book.coverPath != null) {
      final coverFile = File(book.coverPath!);
      if (coverFile.existsSync()) {
        if (mounted) {
          setState(() {
            _coverPath = book.coverPath;
            _coverLoaded = true;
          });
        }
        return;
      }
    }

    final coverService = ref.read(bookCoverServiceProvider);

    // 检查封面服务缓存 - 同步检查
    final cached = coverService.getCachedCoverPath(
      book.filePath,
      book.sourceId,
    );

    if (cached != null) {
      final cachedFile = File(cached);
      if (cachedFile.existsSync()) {
        if (mounted) {
          setState(() {
            _coverPath = cached;
            _coverLoaded = true;
          });
        }
        return;
      }
    }

    // 需要从远程提取封面，使用异步方式
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[book.sourceId];

    if (connection == null) {
      if (mounted) {
        setState(() => _coverLoaded = true);
      }
      return;
    }

    // 异步提取封面（有并发限制）
    final coverPath = await coverService.extractAndCacheCover(
      bookPath: book.filePath,
      sourceId: book.sourceId,
      format: format,
      fileSystem: connection.adapter.fileSystem,
    );

    if (mounted) {
      setState(() {
        _coverPath = coverPath;
        _coverLoaded = true;
      });
    }
  }

  /// 处理可见性变化
  void _onVisibilityChanged(VisibilityInfo info) {
    // 当元素进入可视区域（可见比例 > 0）且之前未可见过
    if (info.visibleFraction > 0 && !_hasBeenVisible) {
      _hasBeenVisible = true;
      // 延迟一帧执行，确保滚动停止后再加载
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadCoverIfNeeded();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.bookEntity;
    final format = book.format;
    // 使用 displayName（优先显示元数据中的书名，其次是文件名）
    final displayName = book.displayName;
    final author = book.author;

    return VisibilityDetector(
      key: Key('book_${book.sourceId}_${book.filePath}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: GestureDetector(
        onTap: widget.isSelectMode
            ? widget.onTap
            : () => _openBook(context, ref),
        onLongPress: widget.isSelectMode ? null : widget.onLongPress ?? () => _showContextMenu(context, ref),
        onSecondaryTap: () => _showContextMenu(context, ref),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面区域（带卡片样式）
            Expanded(
              flex: 4,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: widget.isDark ? 0.3 : 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _buildCover(format),
                    ),
                  ),
                  // 选择模式勾选框
                  if (widget.isSelectMode)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: widget.isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.black.withValues(alpha: 0.3),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white,
                            width: 2,
                          ),
                        ),
                        child: widget.isSelected
                            ? const Icon(Icons.check, color: Colors.white, size: 16)
                            : null,
                      ),
                    ),
                ],
              ),
            ),
            // 标题/作者区域（固定高度，与在线书籍一致）
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: widget.isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    author?.isNotEmpty == true ? author! : '佚名',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建封面区域
  Widget _buildCover(BookFormat format) {
    // 如果有封面图片，显示封面
    if (_coverPath != null) {
      return RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(_coverPath!),
              fit: BoxFit.cover,
              // 限制解码大小，避免大图片占用过多内存
              cacheWidth: 300,
              cacheHeight: 400,
              // 淡入效果
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded) return child;
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  child: child,
                );
              },
              errorBuilder: (context, error, stackTrace) => _buildPlaceholder(format),
            ),
            // 格式标签
            Positioned(
              top: 8,
              right: 8,
              child: _buildFormatBadge(format),
            ),
          ],
        ),
      );
    }

    // 如果正在加载封面，显示加载指示器
    if (!_coverLoaded &&
        (format == BookFormat.epub ||
         format == BookFormat.pdf ||
         format == BookFormat.mobi ||
         format == BookFormat.azw3)) {
      return DecoratedBox(
        decoration: BoxDecoration(gradient: _getFormatGradient(format)),
        child: Stack(
          children: [
            const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white54,
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: _buildFormatBadge(format),
            ),
          ],
        ),
      );
    }

    // 默认显示格式图标
    return _buildPlaceholder(format);
  }

  /// 构建占位符（格式图标）
  Widget _buildPlaceholder(BookFormat format) => DecoratedBox(
        decoration: BoxDecoration(gradient: _getFormatGradient(format)),
        child: Stack(
          children: [
            Center(
              child: Icon(
                _getFormatIcon(format),
                size: 48,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: _buildFormatBadge(format),
            ),
          ],
        ),
      );

  /// 构建格式标签
  Widget _buildFormatBadge(BookFormat format) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          format.name.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  LinearGradient _getFormatGradient(BookFormat format) => switch (format) {
      BookFormat.epub => const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      BookFormat.pdf => const LinearGradient(
          colors: [Color(0xFFEF4444), Color(0xFFF97316)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      BookFormat.txt => const LinearGradient(
          colors: [Color(0xFF6B7280), Color(0xFF9CA3AF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      BookFormat.mobi || BookFormat.azw3 => const LinearGradient(
          colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      BookFormat.unknown => const LinearGradient(
          colors: [Color(0xFF6B7280), Color(0xFF9CA3AF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
    };

  IconData _getFormatIcon(BookFormat format) => switch (format) {
      BookFormat.epub => Icons.auto_stories_rounded,
      BookFormat.pdf => Icons.picture_as_pdf_rounded,
      BookFormat.txt => Icons.description_rounded,
      BookFormat.mobi || BookFormat.azw3 => Icons.book_rounded,
      BookFormat.unknown => Icons.insert_drive_file_rounded,
    };

  Future<void> _openBook(BuildContext context, WidgetRef ref) async {
    final book = widget.bookEntity;
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[book.sourceId];
    if (connection == null) return;

    final file = FileItem(
      name: book.fileName,
      path: book.filePath,
      size: book.size,
      isDirectory: false,
      modifiedTime: book.modifiedTime,
    );
    final url = await connection.adapter.fileSystem.getFileUrl(file.path);
    final bookItem = BookItem.fromFileItem(
      file,
      url,
      sourceId: book.sourceId,
    );

    if (!context.mounted) return;

    // 更新最后阅读时间
    final db = BookDatabaseService();
    await db.updateLastReadTime(book.sourceId, book.filePath);

    // 使用 BookNavigator 打开图书（自动检测漫画并路由到合适的阅读器）
    // 使用 rootNavigatorKey 确保阅读器全屏显示
    await BookNavigator.instance.openBook(
      rootNavigatorKey.currentContext!,
      bookItem,
    );

    // 返回后刷新列表以更新排序
    if (context.mounted) {
      await ref.read(bookListProvider.notifier).loadBooks();
    }
  }

  Future<void> _showContextMenu(BuildContext context, WidgetRef ref) async {
    final book = widget.bookEntity;
    final displayName = book.displayName;

    final favService = ref.read(mediaFavoritesServiceProvider);
    await favService.init();
    final isFav = favService.isFavoriteSync(
      type: MediaType.book,
      sourceId: book.sourceId,
      path: book.filePath,
    );

    if (!context.mounted) return;
    final action = await showMediaFileContextMenu(
      context: context,
      fileName: displayName,
      showShare: true,
      showAddToFavorites: true,
      isFavorite: isFav,
    );

    if (action == null || !context.mounted) return;

    switch (action) {
      case MediaFileAction.removeFromLibrary:
        final confirmed = await showDeleteConfirmDialog(
          context: context,
          title: '从媒体库移除',
          content: '确定要将"$displayName"从媒体库中移除吗？这只会删除缓存数据，不会影响源文件。',
          confirmText: '移除',
          isDestructive: false,
        );
        if (confirmed && context.mounted) {
          await ref.read(bookListProvider.notifier).removeFromLibrary(
                book.sourceId,
                book.filePath,
                displayName,
              );
        }
      case MediaFileAction.deleteFromSource:
        final confirmed = await showDeleteConfirmDialog(
          context: context,
          title: '删除源文件',
          content: '确定要删除"$displayName"吗？此操作将同时删除源文件，无法恢复！',
        );
        if (confirmed && context.mounted) {
          await ref.read(bookListProvider.notifier).deleteFromSource(
                book.sourceId,
                book.filePath,
                displayName,
              );
        }
      case MediaFileAction.share:
        await _shareBook(context, ref, book, displayName);
      case MediaFileAction.addToFavorites:
      case MediaFileAction.removeFromFavorites:
        await ref.read(mediaFavoritesActionsProvider).toggle(
              type: MediaType.book,
              sourceId: book.sourceId,
              path: book.filePath,
              displayName: displayName,
            );
      case MediaFileAction.viewDetails:
      case MediaFileAction.download:
        // 当前菜单未启用这两项；showXxx 默认 false 不会渲染。
        debugPrint('[BookList] MediaFileAction.${action.name} 尚未实现');
    }
  }

  /// 分享图书文件（流式从 NAS 拉到临时目录后调系统分享）
  Future<void> _shareBook(
    BuildContext context,
    WidgetRef ref,
    BookEntity book,
    String displayName,
  ) async {
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[book.sourceId];
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
    // 用文件名（含扩展名）作为分享标题，方便接收方识别格式
    final fileName = book.fileName.isNotEmpty ? book.fileName : displayName;
    final result = await NasFileShareService.shareFromStream(
      fileSystem: connection.adapter.fileSystem,
      path: book.filePath,
      fileName: fileName,
    );
    if (!context.mounted) return;
    if (result.isFailure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享失败：${result.error ?? "未知原因"}')),
      );
    }
  }
}
