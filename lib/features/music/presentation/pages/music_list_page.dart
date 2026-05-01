// ignore_for_file: unused_element

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_glass_app_bar.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/grid_helper.dart';
import 'package:my_nas/core/utils/platform_capabilities.dart';
import 'package:my_nas/core/services/media_scan_progress_service.dart';
import 'package:my_nas/core/utils/background_task_pool.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/music_audio_cache_service.dart';
import 'package:my_nas/features/music/data/services/music_cover_cache_service.dart';
import 'package:my_nas/features/music/data/services/music_database_service.dart';
import 'package:my_nas/features/music/data/services/music_library_cache_service.dart';
import 'package:my_nas/features/music/data/services/music_metadata_service.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/presentation/pages/manual_music_scraper_page.dart';
import 'package:my_nas/features/music/presentation/pages/music_home_page.dart';
import 'package:my_nas/features/music/presentation/pages/music_player_page.dart';
import 'package:my_nas/features/music/presentation/pages/playlist_detail_page.dart';
import 'package:my_nas/features/music/presentation/providers/music_favorites_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/providers/playlist_provider.dart';
import 'package:my_nas/features/music/presentation/widgets/home_layout_sheet.dart';
import 'package:my_nas/features/music/presentation/widgets/mini_player.dart';
import 'package:my_nas/features/music/presentation/widgets/music_queue_sheet.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/media_library_page.dart';
import 'package:my_nas/features/sources/presentation/pages/sources_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/widgets/animated_list_item.dart';
import 'package:my_nas/shared/widgets/context_menu_region.dart';
import 'package:my_nas/shared/widgets/error_widget.dart';
import 'package:my_nas/shared/widgets/media_setup_widget.dart';

/// 音乐文件及其来源
class MusicFileWithSource {
  MusicFileWithSource({
    required this.file,
    required this.sourceId,
    // 元数据字段
    this.title,
    this.artist,
    this.album,
    this.duration,
    this.trackNumber,
    this.year,
    this.genre,
    this.coverBase64,
    this.coverPath,
    this.coverUrl, // 远程封面 URL（用于封面显示的备用）
    this.metadataExtracted = false,
  });

  /// 从缓存条目创建
  factory MusicFileWithSource.fromCacheEntry(MusicLibraryCacheEntry entry) => MusicFileWithSource(
      file: FileItem(
        name: entry.fileName,
        path: entry.filePath,
        size: entry.size,
        isDirectory: false,
        modifiedTime: entry.modifiedTime,
        thumbnailUrl: entry.thumbnailUrl,
      ),
      sourceId: entry.sourceId,
      title: entry.title,
      artist: entry.artist,
      album: entry.album,
      duration: entry.duration,
      trackNumber: entry.trackNumber,
      year: entry.year,
      genre: entry.genre,
      coverBase64: entry.coverBase64,
      metadataExtracted: entry.metadataExtracted,
    );

  final FileItem file;
  final String sourceId;

  // 元数据字段
  final String? title;
  final String? artist;
  final String? album;
  final int? duration; // 毫秒
  final int? trackNumber;
  final int? year;
  final String? genre;
  final String? coverBase64; // Base64 编码的封面图片
  final String? coverPath; // 封面文件路径（磁盘缓存）
  final String? coverUrl; // 远程封面 URL
  final bool metadataExtracted; // 是否已提取过元数据

  String get name => file.name;
  String get path => file.path;
  int get size => file.size;
  DateTime? get modifiedTime => file.modifiedTime;
  String? get thumbnailUrl => file.thumbnailUrl;
  String get displaySize => file.displaySize;

  /// 显示的标题（优先使用元数据标题，否则从文件名解析）
  String get displayTitle {
    if (title != null && title!.isNotEmpty) return title!;
    final nameWithoutExt = name.replaceAll(RegExp(r'\.[^.]+$'), '');
    // 尝试解析 "艺术家 - 歌曲名" 格式
    final match = RegExp(r'^.+?\s*[-–—]\s*(.+)$').firstMatch(nameWithoutExt);
    return match?.group(1)?.trim() ?? nameWithoutExt;
  }

  /// 显示的艺术家
  String get displayArtist {
    if (artist != null && artist!.isNotEmpty) return artist!;
    // 尝试从文件名解析
    final nameWithoutExt = name.replaceAll(RegExp(r'\.[^.]+$'), '');
    final match = RegExp(r'^(.+?)\s*[-–—]\s*.+$').firstMatch(nameWithoutExt);
    return match?.group(1)?.trim() ?? '未知艺术家';
  }

  /// 显示的专辑
  String get displayAlbum => album?.isNotEmpty ?? false ? album! : '未知专辑';

  /// 是否有封面
  bool get hasCover =>
      (coverBase64 != null && coverBase64!.isNotEmpty) ||
      (coverPath != null && coverPath!.isNotEmpty) ||
      (coverUrl != null && coverUrl!.isNotEmpty);

  /// 获取封面数据（从 Base64 解码，优先使用磁盘缓存会在 UI 层处理）
  List<int>? get coverData {
    if (coverBase64 == null || coverBase64!.isEmpty) return null;
    try {
      return base64Decode(coverBase64!);
    } on Exception catch (e) {
      logger.e('解码封面数据失败: $e');
      return null;
    }
  }

  /// 获取封面文件（用于 Image.file）
  /// 注意：不进行同步文件存在检查，避免阻塞 UI 线程
  /// 使用时需配合 Image.file 的 errorBuilder 处理文件不存在的情况
  File? get coverFile {
    if (coverPath == null || coverPath!.isEmpty) return null;
    return File(coverPath!);
  }

  /// 获取封面文件 URL（用于 MusicItem.coverUrl）
  /// 返回 file:// 格式的 URL，供播放器组件使用
  String? get coverFileUrl {
    if (coverPath == null || coverPath!.isEmpty) return null;
    return 'file://$coverPath';
  }

  /// 格式化时长
  String get durationText {
    if (duration == null || duration! <= 0) return '--:--';
    // 过滤异常值：超过 24 小时的时长视为无效
    // 86400000 毫秒 = 24 小时
    if (duration! > 86400000) return '--:--';
    final totalSeconds = duration! ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 唯一标识
  String get uniqueKey => '${sourceId}_$path';

  /// 转换为 MusicItem（用于播放器和收藏功能）
  MusicItem toMusicItem() {
    // 获取封面 URL（如果有磁盘缓存路径）
    String? coverUrl;
    if (coverPath != null && coverPath!.isNotEmpty) {
      coverUrl = 'file://$coverPath';
    }

    return MusicItem(
      id: '${sourceId}_$path',
      name: name,
      path: path,
      url: 'nas://$sourceId$path', // NAS 文件使用此格式，实际播放时会通过代理服务器
      sourceId: sourceId,
      title: title,
      artist: artist,
      album: album,
      duration: duration != null ? Duration(milliseconds: duration!) : null,
      trackNumber: trackNumber,
      year: year,
      genre: genre,
      coverUrl: coverUrl,
      coverData: coverData,
      size: size,
    );
  }

  MusicLibraryCacheEntry toCacheEntry() => MusicLibraryCacheEntry(
        sourceId: sourceId,
        filePath: path,
        fileName: name,
        thumbnailUrl: thumbnailUrl,
        size: size,
        modifiedTime: modifiedTime,
        title: title,
        artist: artist,
        album: album,
        duration: duration,
        trackNumber: trackNumber,
        year: year,
        genre: genre,
        coverBase64: coverBase64,
        metadataExtracted: metadataExtracted,
      );

  /// 复制并更新元数据
  MusicFileWithSource copyWithMetadata({
    String? title,
    String? artist,
    String? album,
    int? duration,
    int? trackNumber,
    int? year,
    String? genre,
    String? coverBase64,
    String? coverPath,
    String? coverUrl,
    bool? metadataExtracted,
  }) => MusicFileWithSource(
      file: file,
      sourceId: sourceId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      trackNumber: trackNumber ?? this.trackNumber,
      year: year ?? this.year,
      genre: genre ?? this.genre,
      coverBase64: coverBase64 ?? this.coverBase64,
      coverPath: coverPath ?? this.coverPath,
      coverUrl: coverUrl ?? this.coverUrl,
      metadataExtracted: metadataExtracted ?? this.metadataExtracted,
    );
}

/// 音乐列表状态
final musicListProvider =
    StateNotifierProvider<MusicListNotifier, MusicListState>(
        MusicListNotifier.new);

/// 音乐来源筛选
enum MusicSourceFilter {
  all('全部'),
  local('本机'),
  remote('NAS');

  const MusicSourceFilter(this.label);
  final String label;
}

/// 判断是否为本机源
bool _isLocalMusicSource(SourceType type) => type == SourceType.local;

/// 动态获取有效的封面路径
/// 参考 recent_tracks_section.dart 中的实现
/// 这个方法可以在沙盒目录 UUID 变化后仍然正确找到缓存文件
String? _getEffectiveCoverPath(MusicFileWithSource track) {
  // 1. 检查直接存储的路径
  if (track.coverPath != null && track.coverPath!.isNotEmpty) {
    if (File(track.coverPath!).existsSync()) {
      return track.coverPath;
    }
  }
  // 2. 动态从缓存服务获取
  final uniqueKey = '${track.sourceId}_${track.path}';
  return MusicCoverCacheService().getCachedCoverPathSync(uniqueKey);
}

sealed class MusicListState {}

class MusicListLoading extends MusicListState {
  MusicListLoading({
    this.progress = 0,
    this.currentFolder,
    this.fromCache = false,
    this.partialTracks = const [],
    this.scannedCount = 0,
    this.phase = MusicScanPhase.scanning,
    this.metadataProgress = 0,
  });
  final double progress;
  final String? currentFolder;
  final bool fromCache;
  final List<MusicFileWithSource> partialTracks;
  final int scannedCount;
  final MusicScanPhase phase;
  final double metadataProgress;
}

/// 扫描阶段
enum MusicScanPhase {
  scanning,
  metadata,
}

/// 音乐排序选项
enum MusicSortOption {
  name('名称', Icons.sort_by_alpha_rounded),
  artist('歌手', Icons.person_rounded),
  album('专辑', Icons.album_rounded),
  dateAdded('添加时间', Icons.schedule_rounded),
  duration('时长', Icons.timer_rounded);

  const MusicSortOption(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// 排序方向
enum SortDirection { ascending, descending }

/// 音乐排序状态
class MusicSortState {
  const MusicSortState({
    this.option = MusicSortOption.name,
    this.direction = SortDirection.ascending,
  });
  final MusicSortOption option;
  final SortDirection direction;

  MusicSortState copyWith({
    MusicSortOption? option,
    SortDirection? direction,
  }) => MusicSortState(
      option: option ?? this.option,
      direction: direction ?? this.direction,
    );
}

/// 音乐排序 Provider
final musicSortProvider = StateProvider<MusicSortState>(
  (ref) => const MusicSortState(),
);

class MusicListNotConnected extends MusicListState {}

/// 优化后的音乐列表状态 - 使用分类数据而非全量内存加载
class MusicListLoaded extends MusicListState {
  MusicListLoaded({
    required this.totalCount,
    this.artistCount = 0,
    this.albumCount = 0,
    this.genreCount = 0,
    this.yearCount = 0,
    this.folderCount = 0,
    this.searchQuery = '',
    this.isLoadingMetadata = false,
    this.metadataProcessed = 0,
    this.metadataTotal = 0,
    this.fromCache = false,
    // 来源筛选
    this.sourceFilter = MusicSourceFilter.all,
    // 多选模式
    this.isSelectMode = false,
    this.selectedPaths = const {},
    // 源类型缓存
    this.sourceTypeCache = const {},
    // 分类数据 - 从 SQLite 分页加载
    this.recentTracks = const [],
    this.allTracks = const [],
    // 搜索结果
    this.searchResults = const [],
    // 用于 O(1) 查找的 Map
    this.trackByPath = const {},
    // 基于 filePath 的备用查找 Map（用于收藏和历史记录）
    this.trackByFilePath = const {},
    // 分页状态
    this.hasMoreTracks = true,
    this.isLoadingMore = false,
  });

  final int totalCount;
  final int artistCount;
  final int albumCount;
  final int genreCount;
  final int yearCount;
  final int folderCount;
  final String searchQuery;
  final bool isLoadingMetadata;
  final int metadataProcessed;
  final int metadataTotal;
  final bool fromCache;

  // 来源筛选
  final MusicSourceFilter sourceFilter;

  // 多选模式
  final bool isSelectMode;
  final Set<String> selectedPaths;

  // 源类型缓存
  final Map<String, SourceType> sourceTypeCache;

  // 分类数据 - 已从 SQLite 加载
  final List<MusicTrackEntity> recentTracks;
  final List<MusicTrackEntity> allTracks;

  // 搜索结果
  final List<MusicTrackEntity> searchResults;

  // 用于 O(1) 查找的 Map（使用 uniqueKey 作为键）
  final Map<String, MusicTrackEntity> trackByPath;

  // 基于 filePath 的备用查找 Map（用于收藏和历史记录）
  final Map<String, MusicTrackEntity> trackByFilePath;

  // 分页状态
  final bool hasMoreTracks; // 是否还有更多歌曲可加载
  final bool isLoadingMore; // 是否正在加载更多

  /// 兼容旧代码：返回当前展示的曲目列表
  List<MusicFileWithSource> get tracks => allTracks
      .map((m) => MusicFileWithSource(
            file: FileItem(
              name: m.fileName,
              path: m.filePath,
              size: m.size ?? 0,
              isDirectory: false,
              modifiedTime: m.modifiedTime,
            ),
            sourceId: m.sourceId,
            title: m.title,
            artist: m.artist,
            album: m.album,
            duration: m.duration,
            year: m.year,
            genre: m.genre,
            coverPath: m.coverPath,
            metadataExtracted: true,
          ))
      .toList();

  /// 过滤后的曲目（应用来源筛选和搜索）
  List<MusicTrackEntity> get filteredMetadata {
    var tracks = searchQuery.isNotEmpty ? searchResults : allTracks;

    // 应用来源筛选
    if (sourceFilter != MusicSourceFilter.all) {
      tracks = tracks.where((t) {
        final sourceType = sourceTypeCache[t.sourceId];
        if (sourceType == null) return true; // 未知类型保留
        final isLocal = _isLocalMusicSource(sourceType);
        return sourceFilter == MusicSourceFilter.local ? isLocal : !isLocal;
      }).toList();
    }

    return tracks;
  }

  /// 判断曲目是否为本机曲目
  bool isLocalTrack(MusicTrackEntity track) {
    final sourceType = sourceTypeCache[track.sourceId];
    if (sourceType == null) return false;
    return _isLocalMusicSource(sourceType);
  }

  /// 获取选中的曲目列表
  List<MusicTrackEntity> get selectedTracks =>
      allTracks.where((t) => selectedPaths.contains(t.filePath)).toList();

  /// 获取选中曲目中本机曲目的数量
  int get selectedLocalCount => selectedTracks.where(isLocalTrack).length;

  /// 获取选中曲目中远程曲目的数量
  int get selectedRemoteCount => selectedTracks.where((t) => !isLocalTrack(t)).length;

  /// 兼容旧代码
  List<MusicFileWithSource> get filteredTracks => filteredMetadata
      .map((m) => MusicFileWithSource(
            file: FileItem(
              name: m.fileName,
              path: m.filePath,
              size: m.size ?? 0,
              isDirectory: false,
              modifiedTime: m.modifiedTime,
            ),
            sourceId: m.sourceId,
            title: m.title,
            artist: m.artist,
            album: m.album,
            duration: m.duration,
            year: m.year,
            genre: m.genre,
            coverPath: m.coverPath,
            metadataExtracted: true,
          ))
      .toList();

  /// 通过路径获取曲目 - O(1) 查找
  MusicFileWithSource? getTrackByPath(String path) {
    final m = trackByPath[path];
    if (m == null) return null;
    return MusicFileWithSource(
      file: FileItem(
        name: m.fileName,
        path: m.filePath,
        size: m.size ?? 0,
        isDirectory: false,
        modifiedTime: m.modifiedTime,
      ),
      sourceId: m.sourceId,
      title: m.title,
      artist: m.artist,
      album: m.album,
      duration: m.duration,
      year: m.year,
      genre: m.genre,
      coverPath: m.coverPath,
      metadataExtracted: true,
    );
  }

  MusicListLoaded copyWith({
    int? totalCount,
    int? artistCount,
    int? albumCount,
    int? genreCount,
    int? yearCount,
    int? folderCount,
    String? searchQuery,
    bool? isLoadingMetadata,
    int? metadataProcessed,
    int? metadataTotal,
    bool? fromCache,
    MusicSourceFilter? sourceFilter,
    bool? isSelectMode,
    Set<String>? selectedPaths,
    Map<String, SourceType>? sourceTypeCache,
    List<MusicTrackEntity>? recentTracks,
    List<MusicTrackEntity>? allTracks,
    List<MusicTrackEntity>? searchResults,
    Map<String, MusicTrackEntity>? trackByPath,
    Map<String, MusicTrackEntity>? trackByFilePath,
    bool? hasMoreTracks,
    bool? isLoadingMore,
  }) =>
      MusicListLoaded(
        totalCount: totalCount ?? this.totalCount,
        artistCount: artistCount ?? this.artistCount,
        albumCount: albumCount ?? this.albumCount,
        genreCount: genreCount ?? this.genreCount,
        yearCount: yearCount ?? this.yearCount,
        folderCount: folderCount ?? this.folderCount,
        searchQuery: searchQuery ?? this.searchQuery,
        isLoadingMetadata: isLoadingMetadata ?? this.isLoadingMetadata,
        metadataProcessed: metadataProcessed ?? this.metadataProcessed,
        metadataTotal: metadataTotal ?? this.metadataTotal,
        fromCache: fromCache ?? this.fromCache,
        sourceFilter: sourceFilter ?? this.sourceFilter,
        isSelectMode: isSelectMode ?? this.isSelectMode,
        selectedPaths: selectedPaths ?? this.selectedPaths,
        sourceTypeCache: sourceTypeCache ?? this.sourceTypeCache,
        recentTracks: recentTracks ?? this.recentTracks,
        allTracks: allTracks ?? this.allTracks,
        searchResults: searchResults ?? this.searchResults,
        trackByPath: trackByPath ?? this.trackByPath,
        trackByFilePath: trackByFilePath ?? this.trackByFilePath,
        hasMoreTracks: hasMoreTracks ?? this.hasMoreTracks,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      );
}

class MusicListError extends MusicListState {
  MusicListError(this.message);
  final String message;
}

class MusicListNotifier extends StateNotifier<MusicListState> {
  MusicListNotifier(this._ref) : super(MusicListLoading()) {
    // 使用 addPostFrameCallback 推迟初始化，确保导航动画不被阻塞
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _init();
    });
  }

  final Ref _ref;
  final MusicLibraryCacheService _cacheService = MusicLibraryCacheService();
  final MusicMetadataService _metadataService = MusicMetadataService();
  final MusicDatabaseService _db = MusicDatabaseService();
  final MusicCoverCacheService _coverCache = MusicCoverCacheService();

  /// 防抖计时器
  Timer? _debounceTimer;

  /// 获取当前启用的媒体库路径
  List<({String sourceId, String path})> _getEnabledPaths() {
    final config = _ref.read(mediaLibraryConfigProvider).valueOrNull;
    if (config == null) return [];

    final paths = config.getEnabledPathsForType(MediaType.music);
    return paths.map((p) => (sourceId: p.sourceId, path: p.path)).toList();
  }

  /// 防抖刷新，避免频繁刷新
  void _scheduleRefresh() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), _loadCategorizedData);
  }

  void _init() {
    logger.d('MusicListNotifier: 开始初始化...');

    // 关键优化：立即显示空状态UI，让用户立即看到界面
    state = MusicListLoaded(totalCount: 0);

    // 在后台初始化服务并加载数据，不阻塞UI
    AppError.fireAndForget(_initAndLoadInBackground(), action: 'musicList.initAndLoadInBackground');
  }

  /// 后台初始化服务并加载数据
  Future<void> _initAndLoadInBackground() async {
    try {
      // 并行初始化服务（使用较短超时保护）
      await Future.wait([
        _cacheService.init(),
        _db.init(),
        _coverCache.init(),
      ]).timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          logger.w('MusicListNotifier: 服务初始化超时');
          return <void>[];
        },
      );

      logger.d('MusicListNotifier: 服务初始化完成');

      // 从 SQLite 加载分类数据
      await _loadCategorizedData();

      // 监听连接状态变化
      _ref.listen<Map<String, SourceConnection>>(activeConnectionsProvider, (previous, next) {
        final prevConnected = previous?.values.where((c) => c.status == SourceStatus.connected).length ?? 0;
        final nextConnected = next.values.where((c) => c.status == SourceStatus.connected).length;

        if (nextConnected > prevConnected && state is MusicListNotConnected) {
          loadMusic();
        }
      });

      // 监听媒体库配置变化（启用/停用/移除路径）
      _ref.listen<AsyncValue<MediaLibraryConfig>>(mediaLibraryConfigProvider, (previous, next) {
        final prevPaths = previous?.valueOrNull?.getEnabledPathsForType(MediaType.music) ?? [];
        final nextPaths = next.valueOrNull?.getEnabledPathsForType(MediaType.music) ?? [];

        // 比较路径是否变化
        final prevKeys = prevPaths.map((p) => '${p.sourceId}|${p.path}').toSet();
        final nextKeys = nextPaths.map((p) => '${p.sourceId}|${p.path}').toSet();

        if (prevKeys.length != nextKeys.length || !prevKeys.containsAll(nextKeys)) {
          logger.i('MusicListNotifier: 媒体库配置变化，刷新音乐列表');
          _scheduleRefresh();
        }
      });
    } on Exception catch (e) {
      logger.e('MusicListNotifier: 初始化失败', e);
      // 保持空列表状态，让用户可以正常使用界面
    }
  }

  /// 每页加载的歌曲数量
  static const int _pageSize = 100;

  /// 从 SQLite 加载分类数据（高性能）
  Future<void> _loadCategorizedData() async {
    state = MusicListLoading(fromCache: true, currentFolder: '加载数据...');

    // 获取启用的路径
    final enabledPaths = _getEnabledPaths();

    // 并行查询统计数据和初始数据（使用路径过滤）
    final results = await Future.wait([
      _db.getStats(enabledPaths: enabledPaths),
      _db.getRecentlyAdded(limit: 20, enabledPaths: enabledPaths),
      _db.getPage(limit: _pageSize, enabledPaths: enabledPaths),
    ]);

    final stats = results[0] as Map<String, dynamic>;
    final recent = results[1] as List<MusicTrackEntity>;
    final allTracks = results[2] as List<MusicTrackEntity>;

    // 验证并修复封面路径（处理重新安装后封面文件丢失的情况）
    final validatedRecent = await _validateCoverPaths(recent);
    final validatedAllTracks = await _validateCoverPaths(allTracks);

    // 构建快速查找 Map
    // 注意：使用 uniqueKey (${sourceId}_$filePath) 作为主键
    // 同时也需要支持通过 filePath 查找（用于收藏和历史记录）
    final trackByPath = <String, MusicTrackEntity>{};
    final trackByFilePath = <String, MusicTrackEntity>{};
    for (final m in validatedAllTracks) {
      trackByPath[m.uniqueKey] = m;
      // 使用 filePath 作为备用查找键
      // 如果有多个来源的同路径文件，后者会覆盖前者，但这在实际中很少发生
      trackByFilePath[m.filePath] = m;
    }

    final total = stats['total'] as int? ?? 0;

    if (total == 0) {
      // 数据库为空，尝试从旧缓存迁移
      await _migrateFromOldCache();
      return;
    }

    // 构建源类型缓存
    final connections = _ref.read(activeConnectionsProvider);
    final sourceTypeCache = <String, SourceType>{};
    for (final entry in connections.entries) {
      sourceTypeCache[entry.key] = entry.value.source.type;
    }

    // 保留之前的筛选状态
    final current = state;
    final previousFilter = current is MusicListLoaded ? current.sourceFilter : MusicSourceFilter.all;

    state = MusicListLoaded(
      totalCount: total,
      artistCount: stats['artists'] as int? ?? 0,
      albumCount: stats['albums'] as int? ?? 0,
      genreCount: stats['genres'] as int? ?? 0,
      yearCount: stats['years'] as int? ?? 0,
      folderCount: stats['folders'] as int? ?? 0,
      recentTracks: validatedRecent,
      allTracks: validatedAllTracks,
      trackByPath: trackByPath,
      trackByFilePath: trackByFilePath,
      sourceTypeCache: sourceTypeCache,
      sourceFilter: previousFilter,
      fromCache: true,
      hasMoreTracks: validatedAllTracks.length < total,
    );

    logger.i('MusicListNotifier: 数据加载完成，已加载 ${validatedAllTracks.length}/$total 首音乐');
  }

  /// 加载更多歌曲（无限滚动）
  Future<void> loadMoreTracks() async {
    final current = state;
    if (current is! MusicListLoaded) return;
    if (current.isLoadingMore || !current.hasMoreTracks) return;

    // 设置加载中状态
    state = current.copyWith(isLoadingMore: true);

    try {
      final offset = current.allTracks.length;
      final enabledPaths = _getEnabledPaths();
      final moreTracks = await _db.getPage(
        limit: _pageSize,
        offset: offset,
        enabledPaths: enabledPaths,
      );

      if (moreTracks.isEmpty) {
        state = current.copyWith(
          hasMoreTracks: false,
          isLoadingMore: false,
        );
        return;
      }

      // 验证封面路径
      final validatedMore = await _validateCoverPaths(moreTracks);

      // 合并歌曲列表
      final newAllTracks = [...current.allTracks, ...validatedMore];

      // 更新快速查找 Map
      final newTrackByPath = Map<String, MusicTrackEntity>.from(current.trackByPath);
      for (final m in validatedMore) {
        newTrackByPath[m.uniqueKey] = m;
      }

      state = current.copyWith(
        allTracks: newAllTracks,
        trackByPath: newTrackByPath,
        hasMoreTracks: newAllTracks.length < current.totalCount,
        isLoadingMore: false,
      );

      logger.d('MusicListNotifier: 加载更多完成，已加载 ${newAllTracks.length}/${current.totalCount}');
    } on Exception catch (e) {
      logger.e('MusicListNotifier: 加载更多失败', e);
      state = current.copyWith(isLoadingMore: false);
    }
  }

  /// 验证封面文件路径是否有效
  /// 如果封面文件不存在，清除 coverPath 引用并更新数据库
  /// 同时启动后台任务重新提取丢失的封面
  Future<List<MusicTrackEntity>> _validateCoverPaths(List<MusicTrackEntity> tracks) async {
    final validatedTracks = <MusicTrackEntity>[];
    final tracksWithMissingCovers = <MusicTrackEntity>[];

    for (final track in tracks) {
      if (track.coverPath != null && track.coverPath!.isNotEmpty) {
        final file = File(track.coverPath!);
        if (await file.exists()) {
          // 封面文件存在，保持不变
          validatedTracks.add(track);
        } else {
          // 封面文件不存在，清除路径引用
          final updatedTrack = track.copyWith(coverPath: null);
          validatedTracks.add(updatedTrack);
          tracksWithMissingCovers.add(updatedTrack);
          logger.d('封面文件不存在，已清除引用: ${track.coverPath}');
        }
      } else {
        validatedTracks.add(track);
      }
    }

    // 批量更新数据库中的无效封面路径
    if (tracksWithMissingCovers.isNotEmpty) {
      logger.i('发现 ${tracksWithMissingCovers.length} 首歌曲的封面文件丢失，正在更新数据库...');
      await _db.upsertBatch(tracksWithMissingCovers);

      // 在后台异步重新提取丢失的封面
      _repairMissingCoversInBackground(tracksWithMissingCovers);
    }

    return validatedTracks;
  }

  /// 后台异步修复丢失的封面
  /// 不阻塞 UI，完成后自动更新状态
  void _repairMissingCoversInBackground(List<MusicTrackEntity> tracksToRepair) {
    // 使用 Future 异步执行，不等待完成
    Future(() async {
      final connections = _ref.read(activeConnectionsProvider);
      if (connections.isEmpty) return;

      await _metadataService.init();
      var repairedCount = 0;
      final updatedTracks = <MusicTrackEntity>[];

      for (final track in tracksToRepair) {
        final connection = connections[track.sourceId];
        if (connection == null || connection.status != SourceStatus.connected) {
          continue;
        }

        try {
          // 从 NAS 重新提取封面
          final metadata = await _metadataService.extractFromNasFile(
            connection.adapter.fileSystem,
            track.filePath,
            skipLyrics: true,
          );

          if (metadata?.coverData != null && metadata!.coverData!.isNotEmpty) {
            // 保存封面到磁盘缓存
            final uniqueKey = '${track.sourceId}_${track.filePath}';
            final coverPath = await _coverCache.saveCover(
              uniqueKey,
              Uint8List.fromList(metadata.coverData!),
            );

            if (coverPath != null) {
              updatedTracks.add(track.copyWith(coverPath: coverPath));
              repairedCount++;
            }
          }
        } on Exception catch (e) {
          logger.w('修复封面失败 ${track.filePath}: $e');
        }
      }

      // 批量更新数据库
      if (updatedTracks.isNotEmpty) {
        await _db.upsertBatch(updatedTracks);
        logger.i('后台修复完成：已恢复 $repairedCount/${tracksToRepair.length} 首歌曲的封面');

        // 通知 UI 刷新（如果状态允许）
        if (state is MusicListLoaded) {
          await _loadCategorizedData();
        }
      }
    });
  }

  /// 从旧缓存迁移数据到 SQLite
  Future<void> _migrateFromOldCache() async {
    final cache = _cacheService.getCache();
    if (cache == null || cache.tracks.isEmpty) {
      state = MusicListLoaded(totalCount: 0, fromCache: true);
      return;
    }

    logger.i('MusicListNotifier: 开始从 Hive 缓存迁移 ${cache.tracks.length} 首音乐');
    state = MusicListLoading(currentFolder: '正在迁移数据...', fromCache: true);

    final metadataList = <MusicTrackEntity>[];
    for (final entry in cache.tracks) {
      // 如果有 Base64 封面，保存到磁盘
      String? coverPath;
      if (entry.coverBase64 != null && entry.coverBase64!.isNotEmpty) {
        final uniqueKey = '${entry.sourceId}_${entry.filePath}';
        coverPath = await _coverCache.saveCoverFromBase64(uniqueKey, entry.coverBase64!);
      }

      metadataList.add(MusicTrackEntity(
        sourceId: entry.sourceId,
        filePath: entry.filePath,
        fileName: entry.fileName,
        title: entry.title,
        artist: entry.artist,
        album: entry.album,
        duration: entry.duration,
        trackNumber: entry.trackNumber,
        year: entry.year,
        genre: entry.genre,
        coverPath: coverPath,
        size: entry.size,
        modifiedTime: entry.modifiedTime,
        lastUpdated: DateTime.now(),
      ));
    }

    // 批量保存到 SQLite
    await _db.upsertBatch(metadataList);
    logger.i('MusicListNotifier: 迁移完成，已保存 ${metadataList.length} 首音乐');

    // 清除旧缓存，防止重复迁移
    await _cacheService.clearCache();
    logger.i('MusicListNotifier: 已清除旧的 Hive 缓存');

    // 重新加载数据
    await _loadCategorizedData();
  }

  /// 加载音乐库
  ///
  /// 注意：无深度限制，会递归扫描所有子目录
  Future<void> loadMusic({bool forceRefresh = false}) async {
    final connections = _ref.read(activeConnectionsProvider);
    final configAsync = _ref.read(mediaLibraryConfigProvider);

    var config = configAsync.valueOrNull;
    if (config == null) {
      state = MusicListLoading(currentFolder: '正在加载配置...');
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final updated = _ref.read(mediaLibraryConfigProvider);
        config = updated.valueOrNull;
        if (config != null) break;
        if (updated.hasError) {
          state = MusicListError('加载媒体库配置失败');
          return;
        }
      }
      if (config == null) {
        state = MusicListLoaded(totalCount: 0);
        return;
      }
    }

    final musicPaths = config.getEnabledPathsForType(MediaType.music);
    if (musicPaths.isEmpty) {
      state = MusicListLoaded(totalCount: 0);
      return;
    }

    final connectedPaths = musicPaths.where((path) {
      final conn = connections[path.sourceId];
      return conn?.status == SourceStatus.connected;
    }).toList();

    if (connectedPaths.isEmpty) {
      final current = state;
      if (current is! MusicListLoaded || current.totalCount == 0) {
        state = MusicListNotConnected();
      }
      return;
    }

    // 如果不是强制刷新且 SQLite 有数据，直接使用
    if (!forceRefresh) {
      final count = await _db.getCount();
      if (count > 0) {
        await _loadCategorizedData();
        return;
      }
    }

    // 渐进式加载：扫描时边扫边保存，立即切换到可用状态
    state = MusicListLoading(currentFolder: '正在扫描...');
    final allTracks = <MusicFileWithSource>[];
    var scannedFolders = 0;
    final totalFolders = connectedPaths.length;
    var lastSaveCount = 0;

    for (final mediaPath in connectedPaths) {
      final connection = connections[mediaPath.sourceId];
      if (connection == null) continue;

      state = MusicListLoading(
        progress: scannedFolders / totalFolders,
        currentFolder: mediaPath.displayName,
        scannedCount: allTracks.length,
      );

      try {
        await _scanForMusic(
          connection.adapter.fileSystem,
          mediaPath.path,
          allTracks,
          sourceId: mediaPath.sourceId,
          onBatchFound: () {
            // 每发现 20 个文件保存一次并更新 UI
            if (allTracks.length - lastSaveCount >= 20) {
              // 异步保存，不阻塞扫描
              _saveTracksAndUpdateUI(
                allTracks.sublist(lastSaveCount),
                connections,
              );
              lastSaveCount = allTracks.length;
            }
          },
        );
      } on Exception catch (e) {
        logger.w('扫描音乐文件夹失败: ${mediaPath.path} - $e');
      }

      scannedFolders++;
    }

    // 保存剩余的音乐
    if (allTracks.length > lastSaveCount) {
      await _saveTracksToDb(allTracks.sublist(lastSaveCount));
    }

    logger.i('音乐扫描完成，共找到 ${allTracks.length} 首音乐');

    // 立即切换到可用状态（用户可以开始使用）
    await _loadCategorizedData();

    // 后台增量提取元数据（不阻塞 UI）
    if (allTracks.isNotEmpty) {
      _extractMetadataInBackground(allTracks, connections);
    }

    logger.i('音乐库加载完成，元数据正在后台提取');
  }

  /// 保存音乐并更新 UI（异步，不阻塞扫描）
  void _saveTracksAndUpdateUI(
    List<MusicFileWithSource> tracks,
    Map<String, SourceConnection> connections,
  ) {
    AppError.fireAndForget(
      _saveTracksToDb(tracks).then((_) async {
        // 保存后刷新 UI
        if (state is MusicListLoading) {
          // 扫描中：更新进度
          final loading = state as MusicListLoading;
          state = MusicListLoading(
            progress: loading.progress,
            currentFolder: loading.currentFolder,
            scannedCount: loading.scannedCount,
          );
        } else if (state is MusicListLoaded) {
          // 已加载：增量更新
          await _loadCategorizedData();
        }
      }),
      action: 'musicList.saveTracksAndUpdateUI',
    );
  }

  /// 保存音乐到数据库（仅基本信息，无元数据）
  Future<void> _saveTracksToDb(List<MusicFileWithSource> tracks) async {
    final entities = tracks.map((t) => MusicTrackEntity(
      sourceId: t.sourceId,
      filePath: t.path,
      fileName: t.name,
      size: t.size,
      modifiedTime: t.modifiedTime,
      lastUpdated: DateTime.now(),
    )).toList();

    await _db.upsertBatch(entities);
  }

  /// 后台增量提取元数据（不阻塞 UI）
  void _extractMetadataInBackground(
    List<MusicFileWithSource> tracks,
    Map<String, SourceConnection> connections,
  ) {
    // 标记正在提取元数据，设置总数
    final current = state;
    if (current is MusicListLoaded) {
      state = current.copyWith(
        isLoadingMetadata: true,
        metadataProcessed: 0,
        metadataTotal: tracks.length,
      );
    }

    AppError.fireAndForget(
      _doExtractMetadataInBackground(tracks, connections),
      action: 'musicList.extractMetadataInBackground',
    );
  }

  /// 并行提取元数据，实时更新进度
  Future<void> _doExtractMetadataInBackground(
    List<MusicFileWithSource> tracks,
    Map<String, SourceConnection> connections,
  ) async {
    await _metadataService.init();

    final totalTracks = tracks.length;
    var processedCount = 0;
    var lastUiRefreshCount = 0;
    final pendingEntities = <MusicTrackEntity>[];
    final lock = Object(); // 用于同步访问共享状态

    logger.i('开始并行提取元数据，共 $totalTracks 首音乐');

    // 使用 BackgroundTaskPool 并行处理
    final futures = <Future<void>>[];

    for (final track in tracks) {
      final connection = connections[track.sourceId];
      if (connection == null || connection.status != SourceStatus.connected) {
        // 源未连接，直接跳过并更新计数
        processedCount++;
        _updateMetadataProgress(processedCount, totalTracks);
        continue;
      }

      // 添加到任务池并行执行
      final future = BackgroundTaskPool.scrape.add(
        () async {
          MusicTrackEntity? entity;

          try {
            final metadata = await _metadataService.extractFromNasFile(
              connection.adapter.fileSystem,
              track.path,
              skipLyrics: true,
            );

            String? coverPath;
            if (metadata?.coverData != null && metadata!.coverData!.isNotEmpty) {
              final uniqueKey = '${track.sourceId}_${track.path}';
              coverPath = await _coverCache.saveCover(
                uniqueKey,
                Uint8List.fromList(metadata.coverData!),
              );
            }

            entity = MusicTrackEntity(
              sourceId: track.sourceId,
              filePath: track.path,
              fileName: track.name,
              title: metadata?.title,
              artist: metadata?.artist,
              album: metadata?.album,
              duration: metadata?.duration?.inMilliseconds,
              trackNumber: metadata?.trackNumber,
              year: metadata?.year,
              genre: metadata?.genre,
              coverPath: coverPath,
              size: track.size,
              modifiedTime: track.modifiedTime,
              lastUpdated: DateTime.now(),
            );
          } on Exception catch (e) {
            logger.w('提取元数据失败 ${track.path}: $e');
          }

          // 同步更新共享状态
          // ignore: unused_local_variable
          final _ = lock; // 使用 lock 标记同步区域
          processedCount++;

          if (entity != null) {
            pendingEntities.add(entity);
          }

          // 实时更新进度（每完成一首就更新）
          _updateMetadataProgress(processedCount, totalTracks);

          // 每处理 10 首保存一次到数据库
          if (pendingEntities.length >= 10) {
            final toSave = List<MusicTrackEntity>.from(pendingEntities);
            pendingEntities.clear();
            await _db.upsertBatch(toSave);
          }

          // 每处理 20 首刷新一次 UI 数据
          if (processedCount - lastUiRefreshCount >= 20) {
            lastUiRefreshCount = processedCount;
            await _loadCategorizedData();
          }
        },
        taskName: 'music_metadata:${track.name}',
      );

      futures.add(future);
    }

    // 等待所有任务完成
    await Future.wait(futures);

    // 保存剩余的数据
    if (pendingEntities.isNotEmpty) {
      await _db.upsertBatch(pendingEntities);
    }

    // 最终刷新 UI
    await _loadCategorizedData();

    // 标记元数据提取完成
    final finalState = state;
    if (finalState is MusicListLoaded) {
      state = finalState.copyWith(
        isLoadingMetadata: false,
        metadataProcessed: totalTracks,
        metadataTotal: totalTracks,
      );
    }

    logger.i('后台元数据提取完成，处理了 $processedCount 首音乐');
  }

  /// 更新元数据提取进度
  void _updateMetadataProgress(int processed, int total) {
    final current = state;
    if (current is MusicListLoaded) {
      state = current.copyWith(
        metadataProcessed: processed,
        metadataTotal: total,
      );
    }
  }

  /// 扫描单个目录（用于媒体库页面的单目录扫描）
  ///
  /// 与 loadMusic 不同，此方法：
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
      logger.w('MusicListNotifier: 源 $sourceId 未连接，跳过扫描');
      return 0;
    }

    // 标记开始扫描
    progressService.startScan(MediaType.music, sourceId, pathPrefix);

    try {
      await _db.init();
      await _metadataService.init();
      await _coverCache.init();

      // 清理该路径的旧数据（避免旧路径格式的数据残留）
      final deletedCount = await _db.deleteByPath(sourceId, pathPrefix);
      if (deletedCount > 0) {
        logger.i('MusicListNotifier: 已清理 $sourceId:$pathPrefix 的 $deletedCount 条旧数据');
      }

      // 阶段1：扫描文件系统
      final tracks = <MusicFileWithSource>[];
      var lastUpdateCount = 0;

      await _scanForMusicWithProgress(
        connection.adapter.fileSystem,
        pathPrefix,
        tracks,
        sourceId: sourceId,
        rootPathPrefix: pathPrefix,
        progressService: progressService,
        onBatchFound: () {
          if (tracks.length - lastUpdateCount >= 5) {
            lastUpdateCount = tracks.length;
            progressService.emitProgress(MediaScanProgress(
              mediaType: MediaType.music,
              phase: MediaScanPhase.scanning,
              sourceId: sourceId,
              pathPrefix: pathPrefix,
              scannedCount: tracks.length,
              currentPath: '$pathPrefix (${tracks.length})',
            ));
          }
        },
      );

      logger.i('MusicListNotifier: 目录 $pathPrefix 扫描完成，找到 ${tracks.length} 首音乐');

      // 阶段2：提取元数据并保存
      if (tracks.isNotEmpty) {
        await _extractAndSaveMetadataWithProgress(
          tracks,
          connections,
          sourceId: sourceId,
          pathPrefix: pathPrefix,
          progressService: progressService,
        );
      }

      // 完成扫描
      progressService.endScan(MediaType.music, sourceId, pathPrefix, success: true);

      // 重新加载数据（更新全局状态）
      await _loadCategorizedData();

      return tracks.length;
    // ignore: avoid_catches_without_on_clauses
    } catch (e, st) {
      // 使用通用 catch 捕获所有类型（SMB 库可能抛出 String 类型异常）
      AppError.handle(e, st, 'MusicListNotifier.scanSinglePath', {'path': pathPrefix});
      logger.e('MusicListNotifier: 扫描目录 $pathPrefix 失败', e);
      progressService.endScan(MediaType.music, sourceId, pathPrefix, success: false);
      rethrow;
    }
  }

  /// 带进度的递归扫描音乐文件
  Future<void> _scanForMusicWithProgress(
    NasFileSystem fs,
    String path,
    List<MusicFileWithSource> tracks, {
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
          await _scanForMusicWithProgress(
            fs,
            item.path,
            tracks,
            sourceId: sourceId,
            rootPathPrefix: rootPathPrefix,
            progressService: progressService,
            onBatchFound: onBatchFound,
          );
        } else if (item.type == FileType.audio) {
          tracks.add(MusicFileWithSource(file: item, sourceId: sourceId));
          onBatchFound?.call();
        }
      }
    // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      // 使用通用 catch 捕获所有类型（SMB 库可能抛出 String 类型异常）
      logger.w('扫描子文件夹失败: $path - $e');
    }
  }

  /// 带进度的元数据提取和保存
  Future<void> _extractAndSaveMetadataWithProgress(
    List<MusicFileWithSource> tracks,
    Map<String, SourceConnection> connections, {
    required String sourceId,
    required String pathPrefix,
    required MediaScanProgressService progressService,
  }) async {
    final totalTracks = tracks.length;
    var processedCount = 0;
    final metadataList = <MusicTrackEntity>[];

    progressService.emitProgress(MediaScanProgress(
      mediaType: MediaType.music,
      phase: MediaScanPhase.processing,
      sourceId: sourceId,
      pathPrefix: pathPrefix,
      scannedCount: 0,
      totalCount: totalTracks,
      currentFile: '准备提取元数据...',
    ));

    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      final connection = connections[track.sourceId];

      if (connection == null || connection.status != SourceStatus.connected) {
        processedCount++;
        continue;
      }

      try {
        final metadata = await _metadataService.extractFromNasFile(
          connection.adapter.fileSystem,
          track.path,
          skipLyrics: true,
        );

        String? coverPath;
        if (metadata?.coverData != null && metadata!.coverData!.isNotEmpty) {
          final uniqueKey = '${track.sourceId}_${track.path}';
          coverPath = await _coverCache.saveCover(
            uniqueKey,
            Uint8List.fromList(metadata.coverData!),
          );
        }

        metadataList.add(MusicTrackEntity(
          sourceId: track.sourceId,
          filePath: track.path,
          fileName: track.name,
          title: metadata?.title,
          artist: metadata?.artist,
          album: metadata?.album,
          duration: metadata?.duration?.inMilliseconds,
          trackNumber: metadata?.trackNumber,
          year: metadata?.year,
          genre: metadata?.genre,
          coverPath: coverPath,
          size: track.size,
          modifiedTime: track.modifiedTime,
          lastUpdated: DateTime.now(),
        ));
      } on Exception catch (e) {
        logger.w('提取元数据失败 ${track.path}: $e');
        metadataList.add(MusicTrackEntity(
          sourceId: track.sourceId,
          filePath: track.path,
          fileName: track.name,
          size: track.size,
          modifiedTime: track.modifiedTime,
          lastUpdated: DateTime.now(),
        ));
      }

      processedCount++;

      // 实时发送进度（UI 端做节流处理）
      progressService.emitProgress(MediaScanProgress(
        mediaType: MediaType.music,
        phase: MediaScanPhase.processing,
        sourceId: sourceId,
        pathPrefix: pathPrefix,
        scannedCount: processedCount,
        totalCount: totalTracks,
        currentFile: '提取元数据',
      ));

      // 批量保存数据库（保持 10 条一批以优化 I/O）
      if (processedCount % 10 == 0 || processedCount == totalTracks) {
        await _db.upsertBatch(metadataList);
        metadataList.clear();

        // 边扫边显示：使用防抖刷新 UI（300ms 节流）
        _scheduleRefresh();
      }
    }

    if (metadataList.isNotEmpty) {
      await _db.upsertBatch(metadataList);
    }

    logger.i('目录 $pathPrefix 元数据提取完成，处理了 $processedCount 首音乐');
  }

  /// 递归扫描音乐文件（无深度限制）
  ///
  /// 会跳过以下目录：
  /// - 隐藏目录（以 . 开头）
  /// - 系统目录（以 @ 开头、#recycle）
  Future<void> _scanForMusic(
    NasFileSystem fs,
    String path,
    List<MusicFileWithSource> tracks, {
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
          await _scanForMusic(
            fs,
            item.path,
            tracks,
            sourceId: sourceId,
            onBatchFound: onBatchFound,
          );
        } else if (item.type == FileType.audio) {
          tracks.add(MusicFileWithSource(file: item, sourceId: sourceId));
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

  void setSearchQuery(String query) {
    final current = state;
    if (current is MusicListLoaded) {
      if (query.isEmpty) {
        state = current.copyWith(searchQuery: '', searchResults: []);
      } else {
        _performSearch(query, current);
      }
    }
  }

  /// 执行搜索（使用 SQLite LIKE 查询）
  Future<void> _performSearch(String query, MusicListLoaded current) async {
    state = current.copyWith(searchQuery: query, isLoadingMetadata: true);

    final results = await _db.search(query, limit: 100);

    final newState = state;
    if (newState is MusicListLoaded && newState.searchQuery == query) {
      state = newState.copyWith(
        searchResults: results,
        isLoadingMetadata: false,
      );
    }
  }

  /// 强制刷新
  Future<void> forceRefresh() async {
    await _db.clearAll();
    await _coverCache.clearAll();
    // 同时清除音频文件缓存，避免播放过时的缓存文件
    await MusicAudioCacheService().clearAll();
    await loadMusic(forceRefresh: true);
  }

  /// 从媒体库移除音乐（只删除数据库记录，不删除源文件）
  Future<bool> removeFromLibrary(String sourceId, String filePath, String displayTitle) async {
    try {
      await _db.delete(sourceId, filePath);
      await _loadCategorizedData();
      logger.i('MusicListNotifier: 已从媒体库移除 $displayTitle');
      return true;
    } on Exception catch (e) {
      logger.e('MusicListNotifier: 移除音乐失败', e);
      return false;
    }
  }

  /// 删除音乐源文件（同时删除数据库记录和源文件）
  Future<bool> deleteFromSource(String sourceId, String filePath, String displayTitle) async {
    try {
      final connections = _ref.read(activeConnectionsProvider);
      final connection = connections[sourceId];
      if (connection == null || connection.status != SourceStatus.connected) {
        logger.w('MusicListNotifier: 无法删除，源未连接');
        return false;
      }

      await connection.adapter.fileSystem.delete(filePath);
      await _db.delete(sourceId, filePath);
      await _loadCategorizedData();

      logger.i('MusicListNotifier: 已删除源文件 $displayTitle');
      return true;
    } on Exception catch (e) {
      logger.e('MusicListNotifier: 删除音乐源文件失败', e);
      return false;
    }
  }

  /// 更新单个曲目的元数据（刮削后调用）
  Future<void> refreshTrackMetadata(String sourceId, String filePath) async {
    final current = state;
    if (current is! MusicListLoaded) return;

    try {
      // 从数据库获取最新数据
      final dbTrack = await _db.get(sourceId, filePath);
      if (dbTrack == null) return;

      // 构建更新后的曲目
      MusicTrackEntity? updatedTrack;

      // 在当前状态中找到对应的曲目并更新
      final updatedTracks = current.allTracks.map((track) {
        if (track.sourceId == sourceId && track.filePath == filePath) {
          updatedTrack = track.copyWith(
            title: dbTrack.title ?? track.title,
            artist: dbTrack.artist ?? track.artist,
            album: dbTrack.album ?? track.album,
            coverPath: dbTrack.coverPath ?? track.coverPath,
            year: dbTrack.year ?? track.year,
            trackNumber: dbTrack.trackNumber ?? track.trackNumber,
            genre: dbTrack.genre ?? track.genre,
            lastUpdated: DateTime.now(),
          );
          return updatedTrack!;
        }
        return track;
      }).toList();

      // 同时更新 trackByFilePath 映射
      final updatedTrackByFilePath = Map<String, MusicTrackEntity>.from(current.trackByFilePath);
      if (updatedTrack != null) {
        updatedTrackByFilePath[filePath] = updatedTrack!;
      }

      // 更新状态
      state = current.copyWith(
        allTracks: updatedTracks,
        trackByFilePath: updatedTrackByFilePath,
      );
      logger.d('MusicListNotifier: 已更新曲目元数据 $filePath');
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '更新曲目元数据失败');
    }
  }

  /// 设置来源筛选
  void setSourceFilter(MusicSourceFilter filter) {
    final current = state;
    if (current is MusicListLoaded) {
      state = current.copyWith(sourceFilter: filter);
    }
  }

  /// 切换多选模式
  void toggleSelectMode() {
    final current = state;
    if (current is MusicListLoaded) {
      state = current.copyWith(
        isSelectMode: !current.isSelectMode,
        selectedPaths: {},
      );
    }
  }

  /// 进入多选模式
  void enterSelectMode() {
    final current = state;
    if (current is MusicListLoaded && !current.isSelectMode) {
      state = current.copyWith(isSelectMode: true);
    }
  }

  /// 退出多选模式
  void exitSelectMode() {
    final current = state;
    if (current is MusicListLoaded && current.isSelectMode) {
      state = current.copyWith(isSelectMode: false, selectedPaths: {});
    }
  }

  /// 切换曲目选择状态
  void toggleTrackSelection(String filePath) {
    final current = state;
    if (current is MusicListLoaded) {
      final newSelected = Set<String>.from(current.selectedPaths);
      if (newSelected.contains(filePath)) {
        newSelected.remove(filePath);
      } else {
        newSelected.add(filePath);
      }
      state = current.copyWith(selectedPaths: newSelected);
    }
  }

  /// 选择所有当前显示的曲目
  void selectAll() {
    final current = state;
    if (current is MusicListLoaded) {
      final allPaths = current.filteredMetadata.map((t) => t.filePath).toSet();
      state = current.copyWith(selectedPaths: allPaths);
    }
  }

  /// 清空选择
  void clearSelection() {
    final current = state;
    if (current is MusicListLoaded) {
      state = current.copyWith(selectedPaths: {});
    }
  }
}

/// 音乐分类Tab枚举
/// 音乐库分类
enum MusicCategory {
  all('全部歌曲', Icons.queue_music_rounded),
  artists('艺术家', Icons.person_rounded),
  albums('专辑', Icons.album_rounded),
  folders('文件夹', Icons.folder_rounded),
  favorites('我喜欢', Icons.favorite_rounded),
  recent('最近播放', Icons.history_rounded),
  genres('流派', Icons.category_rounded),
  years('年代', Icons.date_range_rounded),
  playlists('歌单', Icons.playlist_play_rounded);

  const MusicCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

class MusicListPage extends ConsumerStatefulWidget {
  const MusicListPage({super.key});

  @override
  ConsumerState<MusicListPage> createState() => _MusicListPageState();
}

class _MusicListPageState extends ConsumerState<MusicListPage> {
  final _searchController = TextEditingController();
  bool _showSearch = false;

  /// 上一次 didChangeDependencies 时的路由路径
  /// 用于检测路由变化并在必要时重置搜索状态
  String? _lastRoutePath;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // 检测路由变化，当从其他 Tab 返回时重置搜索模式
    try {
      final currentPath = GoRouterState.of(context).uri.path;
      final previousPath = _lastRoutePath;
      _lastRoutePath = currentPath;

      // 如果之前在其他 Tab（非音乐页面），现在回到音乐页面，且搜索模式开启
      // 则重置搜索状态，让用户看到主界面
      if (previousPath != null &&
          previousPath != currentPath &&
          currentPath == '/music' &&
          _showSearch) {
        // 使用 addPostFrameCallback 避免在 build 过程中调用 setState
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _showSearch) {
            setState(() => _showSearch = false);
            _searchController.clear();
            ref.read(musicListProvider.notifier).setSearchQuery('');
          }
        });
      }
    } catch (_) {
      // GoRouterState.of 可能在某些情况下抛出异常，忽略
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
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
    final state = ref.watch(musicListProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uiStyle = ref.watch(uiStyleProvider);
    final safeTop = MediaQuery.of(context).padding.top;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    // iOS 26 Liquid Glass 风格：悬浮布局
    if (uiStyle.isGlass) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
        body: Stack(
          children: [
            // 主内容（包含大标题）
            Column(
              children: [
                Expanded(
                  child: switch (state) {
                    MusicListLoading(
                      :final progress,
                      :final currentFolder,
                      :final fromCache,
                      :final partialTracks,
                      :final scannedCount,
                    ) =>
                      _buildLoadingState(
                        context,
                        progress,
                        currentFolder,
                        fromCache,
                        partialTracks,
                        scannedCount,
                        isDark,
                      ),
                    MusicListNotConnected() => const MediaSetupWidget(
                        mediaType: MediaType.music,
                        icon: Icons.library_music_outlined,
                      ),
                    MusicListError(:final message) => AppErrorWidget(
                        message: message,
                        onRetry: () => ref.read(musicListProvider.notifier).loadMusic(),
                      ),
                    MusicListLoaded(:final filteredTracks) when filteredTracks.isEmpty =>
                      _buildEmptyState(context, ref, isDark),
                    final MusicListLoaded loaded =>
                      _buildMusicContentWithLargeTitle(context, ref, loaded, isDark, safeTop),
                  },
                ),
                // MiniPlayer 在 glass 模式下也需要显示（搜索模式或非 loaded 状态）
                if (state case MusicListLoaded(:final searchQuery) when searchQuery.isNotEmpty)
                  const MiniPlayer()
                else if (state is! MusicListLoaded)
                  const MiniPlayer(),
              ],
            ),
            if (_showSearch)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => setState(() => _showSearch = false),
                ),
              ),
            // 悬浮按钮组（右上角）
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              top: _showSearch ? null : safeTop + 8,
              right: 16,
              bottom: _showSearch ? (keyboardInset > 0 ? keyboardInset + 16 : bottomPadding + 16) : null,
              child: _showSearch
                  ? _buildFloatingSearchBar(context, ref, isDark)
                  : _buildFloatingButtons(context, ref, isDark, state),
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
              MusicListLoading(
                :final progress,
                :final currentFolder,
                :final fromCache,
                :final partialTracks,
                :final scannedCount,
              ) =>
                _buildLoadingState(
                  context,
                  progress,
                  currentFolder,
                  fromCache,
                  partialTracks,
                  scannedCount,
                  isDark,
                ),
              MusicListNotConnected() => const MediaSetupWidget(
                  mediaType: MediaType.music,
                  icon: Icons.library_music_outlined,
                ),
              MusicListError(:final message) => AppErrorWidget(
                  message: message,
                  onRetry: () => ref.read(musicListProvider.notifier).loadMusic(),
                ),
              MusicListLoaded(:final filteredTracks) when filteredTracks.isEmpty =>
                _buildEmptyState(context, ref, isDark),
              final MusicListLoaded loaded => _buildHomeContent(context, ref, loaded, isDark),
            },
          ),
          // 首页有 HeroPlayerCard，不显示底部迷你播放器
          // 只在非首页状态（加载中、未连接、错误、空状态）或搜索模式下显示迷你播放器
          if (state case MusicListLoaded(:final searchQuery) when searchQuery.isNotEmpty)
            const MiniPlayer()
          else if (state is! MusicListLoaded)
            const MiniPlayer(),
        ],
      ),
    );
  }

  /// 构建首页头部
  Widget _buildHeader(BuildContext context, WidgetRef ref, bool isDark, MusicListState state) {
    final uiStyle = ref.watch(uiStyleProvider);

    // 玻璃模式下的染色
    final tintColor = uiStyle.isGlass
        ? (isDark
            ? Colors.deepOrange.withValues(alpha: 0.15)
            : Colors.deepOrange.withValues(alpha: 0.08))
        : null;

    return AdaptiveGlassHeader(
      height: 72,
      backgroundColor: uiStyle.isGlass
          ? tintColor
          : (isDark
              ? const Color(0xFF2E1A1A) // 深红棕色调
              : Colors.deepOrange.withValues(alpha: 0.08)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.appBarHorizontalPadding,
          AppSpacing.appBarVerticalPadding,
          AppSpacing.appBarHorizontalPadding,
          AppSpacing.lg, // 底部保持较大间距用于 header 效果
        ),
        child: _showSearch
            ? _buildSearchBar(context, ref, isDark)
            : _buildGreetingHeader(context, ref, isDark, state),
      ),
    );
  }

  /// 问候语头部
  Widget _buildGreetingHeader(BuildContext context, WidgetRef ref, bool isDark, MusicListState state) {
    final trackCount = state is MusicListLoaded ? state.totalCount : 0;
    final isLoadingMetadata = state is MusicListLoaded && state.isLoadingMetadata;
    final metadataProcessed = state is MusicListLoaded ? state.metadataProcessed : 0;
    final metadataTotal = state is MusicListLoaded ? state.metadataTotal : 0;

    return Row(
      children: [
        Expanded(
          // 使用 Expanded 确保左侧内容填满可用空间，按钮自动靠右
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (trackCount > 0)
                Row(
                  children: [
                    Text(
                      '共 $trackCount 首歌曲',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                      ),
                    ),
                    if (isLoadingMetadata) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: isDark ? Colors.deepOrange[300] : Colors.deepOrange,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          metadataTotal > 0
                              ? '提取元数据 $metadataProcessed/$metadataTotal'
                              : '正在加载元数据...',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.grey[500] : Colors.grey[500],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
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
            GlassGroupIconButton(
              icon: Icons.queue_music_rounded,
              onPressed: () => showMusicQueueSheet(context),
              tooltip: '播放队列',
            ),
            GlassGroupPopupMenuButton<String>(
              icon: Icons.more_vert_rounded,
              tooltip: '更多',
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'layout',
                  child: Row(
                    children: const [
                      Icon(Icons.dashboard_customize_rounded, size: 20),
                      SizedBox(width: 12),
                      Text('首页布局'),
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
              onSelected: _handleMusicMenuSelection,
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
            ref.read(musicListProvider.notifier).setSearchQuery('');
          },
          icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.black87),
        ),
        Expanded(
          child: TextField(
            controller: _searchController,
            autofocus: true,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: '搜索歌曲、艺术家、专辑...',
              hintStyle: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[400]),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onChanged: (value) {
              ref.read(musicListProvider.notifier).setSearchQuery(value);
            },
          ),
        ),
        if (_searchController.text.isNotEmpty)
          IconButton(
            onPressed: () {
              _searchController.clear();
              ref.read(musicListProvider.notifier).setSearchQuery('');
              // 同时关闭搜索界面
              setState(() => _showSearch = false);
            },
            icon: Icon(Icons.close, color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
          ),
      ],
    );

  /// iOS 26 悬浮按钮组
  Widget _buildFloatingButtons(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    MusicListState state,
  ) {
    return GlassButtonGroup(
      children: [
        GlassGroupIconButton(
          icon: Icons.search_rounded,
          onPressed: () => setState(() => _showSearch = true),
          tooltip: '搜索',
        ),
        GlassGroupIconButton(
          icon: Icons.queue_music_rounded,
          onPressed: () => showMusicQueueSheet(context),
          tooltip: '播放队列',
        ),
        GlassGroupPopupMenuButton<String>(
          icon: Icons.more_vert_rounded,
          tooltip: '更多',
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'layout',
              child: Row(
                children: const [
                  Icon(Icons.dashboard_customize_rounded, size: 20),
                  SizedBox(width: 12),
                  Text('首页布局'),
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
          onSelected: _handleMusicMenuSelection,
        ),
      ],
    );
  }

  /// 音乐菜单选择处理
  void _handleMusicMenuSelection(String value) {
    debugPrint('_handleMusicMenuSelection: called with value: $value, mounted: $mounted');
    if (!mounted) return;
    switch (value) {
      case 'layout':
        debugPrint('_handleMusicMenuSelection: showing home layout sheet');
        showHomeLayoutSheet(context);
      case 'library':
        debugPrint('_handleMusicMenuSelection: navigating to media library');
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => const MediaLibraryPage(),
          ),
        );
      case 'sources':
        debugPrint('_handleMusicMenuSelection: navigating to sources');
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
      hintText: '搜索歌曲、艺术家...',
      width: searchWidth,
      onChanged: (query) {
        ref.read(musicListProvider.notifier).setSearchQuery(query);
      },
      onClose: () {
        setState(() => _showSearch = false);
      },
    );
  }

  /// iOS 26 带大标题的音乐内容
  Widget _buildMusicContentWithLargeTitle(
    BuildContext context,
    WidgetRef ref,
    MusicListLoaded state,
    bool isDark,
    double safeTop,
  ) {
    // 如果有搜索，显示搜索结果
    if (state.searchQuery.isNotEmpty) {
      return _buildSearchResults(context, ref, state, isDark);
    }

    // 获取收藏和历史状态
    final favoritesState = ref.watch(musicFavoritesProvider);
    final historyState = ref.watch(musicHistoryProvider);

    // 转换收藏为 MusicFileWithSource
    final favoriteTracks = favoritesState.favorites
        .where((fav) => state.trackByFilePath.containsKey(fav.musicPath))
        .map((fav) {
          final m = state.trackByFilePath[fav.musicPath]!;
          return MusicFileWithSource(
            file: FileItem(
              name: m.fileName,
              path: m.filePath,
              size: m.size ?? 0,
              isDirectory: false,
              modifiedTime: m.modifiedTime,
            ),
            sourceId: m.sourceId,
            title: m.title,
            artist: m.artist,
            album: m.album,
            duration: m.duration,
            year: m.year,
            genre: m.genre,
            coverPath: m.coverPath,
            metadataExtracted: true,
          );
        })
        .toList();

    // 转换历史为 MusicFileWithSource
    final recentTracks = historyState.history
        .take(20)
        .where((h) => state.trackByFilePath.containsKey(h.musicPath))
        .map((h) {
          final m = state.trackByFilePath[h.musicPath]!;
          String? effectiveCoverPath = m.coverPath;
          String? effectiveCoverUrl;

          if (effectiveCoverPath == null || effectiveCoverPath.isEmpty) {
            if (h.coverUrl != null && h.coverUrl!.isNotEmpty) {
              if (h.coverUrl!.startsWith('file://')) {
                effectiveCoverPath = h.coverUrl!.replaceFirst('file://', '');
              } else {
                effectiveCoverUrl = h.coverUrl;
              }
            }
          }

          return MusicFileWithSource(
            file: FileItem(
              name: m.fileName,
              path: m.filePath,
              size: m.size ?? 0,
              isDirectory: false,
              modifiedTime: m.modifiedTime,
            ),
            sourceId: m.sourceId,
            title: m.title,
            artist: m.artist,
            album: m.album,
            duration: m.duration,
            year: m.year,
            genre: m.genre,
            coverPath: effectiveCoverPath,
            coverUrl: effectiveCoverUrl,
            metadataExtracted: true,
          );
        })
        .toList();

    // 获取歌单数量
    final playlistState = ref.watch(playlistProvider);
    final playlistCount = playlistState.playlists.length;

    return CustomScrollView(
      slivers: [
        // 顶部安全区域留白
        SliverPadding(padding: EdgeInsets.only(top: safeTop + 8)),
        // 大标题区域（iOS 26 风格）- 右侧留出浮动按钮空间
        _buildLargeTitleSliver(context, state, isDark, hasFloatingButtons: true),
        // 内容区域（使用 returnSlivers 模式避免嵌套滚动）
        SliverToBoxAdapter(
          child: MusicHomeContent(
            tracks: state.tracks,
            recentTracks: recentTracks,
            favoriteTracks: favoriteTracks,
            totalCount: state.totalCount,
            artistCount: state.artistCount,
            albumCount: state.albumCount,
            genreCount: state.genreCount,
            yearCount: state.yearCount,
            folderCount: state.folderCount,
            playlistCount: playlistCount,
            favoritesCount: favoritesState.favorites.length,
            recentCount: historyState.history.length,
            onTrackTap: (track, allTracks) => _playTrack(context, ref, track, allTracks),
            onCategoryTap: (category) => _navigateToCategory(context, category, state),
            onShuffleTap: () => _shufflePlay(context, ref, state.tracks),
            returnSlivers: true,
          ),
        ),
        // 底部留白 - 使用 SliverToBoxAdapter 确保正确添加底部空间
        SliverToBoxAdapter(
          child: SizedBox(height: context.scrollBottomPadding + 20),
        ),
      ],
    );
  }

  /// iOS 26 大标题 Sliver
  Widget _buildLargeTitleSliver(
    BuildContext context,
    MusicListLoaded state,
    bool isDark, {
    bool hasFloatingButtons = false,
  }) {
    final trackCount = state.totalCount;
    final artistCount = state.artistCount;
    final albumCount = state.albumCount;
    final isLoadingMetadata = state.isLoadingMetadata;
    final metadataProcessed = state.metadataProcessed;
    final metadataTotal = state.metadataTotal;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 大标题 - 需要避开浮动按钮
            Padding(
              padding: EdgeInsets.only(right: hasFloatingButtons ? 150 : 0),
              child: Text(
                _getGreeting(),
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 统计信息 - 横向排列，可以延伸到按钮下方
            if (trackCount > 0 || isLoadingMetadata)
              Row(
                children: [
                  _buildStatChip(
                    icon: Icons.music_note_rounded,
                    label: '$trackCount 首歌曲',
                    isDark: isDark,
                  ),
                  if (artistCount > 0) ...[
                    const SizedBox(width: 12),
                    _buildStatChip(
                      icon: Icons.person_rounded,
                      label: '$artistCount 位',
                      isDark: isDark,
                    ),
                  ],
                  if (albumCount > 0) ...[
                    const SizedBox(width: 12),
                    _buildStatChip(
                      icon: Icons.album_rounded,
                      label: '$albumCount 张',
                      isDark: isDark,
                    ),
                  ],
                  if (isLoadingMetadata) ...[
                    const SizedBox(width: 12),
                    _buildStatChip(
                      icon: Icons.sync_rounded,
                      label: metadataTotal > 0
                          ? '$metadataProcessed/$metadataTotal'
                          : '加载中',
                      isDark: isDark,
                      isLoading: true,
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// 统计信息小标签
  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required bool isDark,
    bool isLoading = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoading)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: isDark ? Colors.deepOrange[300] : Colors.deepOrange,
              ),
            )
          else
            Icon(
              icon,
              size: 14,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建首页内容（现代化设计）
  Widget _buildHomeContent(BuildContext context, WidgetRef ref, MusicListLoaded state, bool isDark) {
    // 如果正在搜索，显示搜索结果
    if (state.searchQuery.isNotEmpty) {
      return _buildSearchResults(context, ref, state, isDark);
    }

    // 获取收藏和历史状态
    final favoritesState = ref.watch(musicFavoritesProvider);
    final historyState = ref.watch(musicHistoryProvider);

    // 转换收藏为 MusicFileWithSource
    // 注意：收藏存储的是 musicPath (filePath)，需要使用 trackByFilePath 查找
    final favoriteTracks = favoritesState.favorites
        .where((fav) => state.trackByFilePath.containsKey(fav.musicPath))
        .map((fav) {
          final m = state.trackByFilePath[fav.musicPath]!;
          return MusicFileWithSource(
            file: FileItem(
              name: m.fileName,
              path: m.filePath,
              size: m.size ?? 0,
              isDirectory: false,
              modifiedTime: m.modifiedTime,
            ),
            sourceId: m.sourceId,
            title: m.title,
            artist: m.artist,
            album: m.album,
            duration: m.duration,
            year: m.year,
            genre: m.genre,
            coverPath: m.coverPath,
            metadataExtracted: true,
          );
        })
        .toList();

    // 转换历史为 MusicFileWithSource
    // 注意：历史存储的是 musicPath (filePath)，需要使用 trackByFilePath 查找
    final recentTracks = historyState.history
        .take(20)
        .where((h) => state.trackByFilePath.containsKey(h.musicPath))
        .map((h) {
          final m = state.trackByFilePath[h.musicPath]!;

          // 优先使用数据库中的 coverPath，如果没有则尝试从历史的 coverUrl 获取
          String? effectiveCoverPath = m.coverPath;
          String? effectiveCoverUrl;

          if (effectiveCoverPath == null || effectiveCoverPath.isEmpty) {
            if (h.coverUrl != null && h.coverUrl!.isNotEmpty) {
              // 如果历史记录有 file:// 格式的封面 URL，提取路径
              if (h.coverUrl!.startsWith('file://')) {
                effectiveCoverPath = h.coverUrl!.replaceFirst('file://', '');
              } else {
                // 远程 URL
                effectiveCoverUrl = h.coverUrl;
              }
            }
          }

          return MusicFileWithSource(
            file: FileItem(
              name: m.fileName,
              path: m.filePath,
              size: m.size ?? 0,
              isDirectory: false,
              modifiedTime: m.modifiedTime,
            ),
            sourceId: m.sourceId,
            title: m.title,
            artist: m.artist,
            album: m.album,
            duration: m.duration,
            year: m.year,
            genre: m.genre,
            coverPath: effectiveCoverPath,
            coverUrl: effectiveCoverUrl,
            metadataExtracted: true,
          );
        })
        .toList();

    // 获取歌单数量
    final playlistState = ref.watch(playlistProvider);
    final playlistCount = playlistState.playlists.length;

    return MusicHomeContent(
      tracks: state.tracks,
      recentTracks: recentTracks,
      favoriteTracks: favoriteTracks,
      totalCount: state.totalCount,
      artistCount: state.artistCount,
      albumCount: state.albumCount,
      genreCount: state.genreCount,
      yearCount: state.yearCount,
      folderCount: state.folderCount,
      playlistCount: playlistCount,
      favoritesCount: favoritesState.favorites.length, // 直接使用收藏列表长度
      recentCount: historyState.history.length, // 直接使用历史列表长度
      onTrackTap: (track, allTracks) => _playTrack(context, ref, track, allTracks),
      onCategoryTap: (category) => _navigateToCategory(context, category, state),
      onShuffleTap: () => _shufflePlay(context, ref, state.tracks),
    );
  }

  /// 搜索结果
  Widget _buildSearchResults(BuildContext context, WidgetRef ref, MusicListLoaded state, bool isDark) {
    final results = state.filteredTracks;
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '未找到 "${state.searchQuery}" 相关歌曲',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    // 搜索结果不使用 RefreshIndicator，避免下拉触发重新扫描
    return CustomScrollView(
      slivers: [
        // 顶部安全区域留白（避免与状态栏重叠）
        SliverPadding(padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top)),
        // 音乐列表
        SliverPadding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => AnimatedListItem(
                index: index,
                child: _MusicListTile(
                  track: state.filteredTracks[index],
                  index: index,
                  isDark: isDark,
                ),
              ),
              childCount: state.filteredTracks.length,
            ),
          ),
        ),
        // 底部留白 - 使用动态值适配不同模式的导航栏高度
        SliverToBoxAdapter(child: SizedBox(height: context.scrollBottomPadding + 20)),
      ],
    );
  }

  void _navigateToCategory(BuildContext context, MusicCategory category, MusicListLoaded state) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => category == MusicCategory.all
            ? AllSongsPage(tracks: state.tracks)
            : _MusicCategoryPage(
                category: category,
              ),
      ),
    );
  }

  Future<void> _playTrack(BuildContext context, WidgetRef ref, MusicFileWithSource track, List<MusicFileWithSource> allTracks) async {
    logger.i('_playTrack: 开始播放 ${track.name}');

    // 提前获取所有需要的 provider（避免异步后使用 ref）
    final connections = ref.read(activeConnectionsProvider);
    final playQueueNotifier = ref.read(playQueueProvider.notifier);
    final playerNotifier = ref.read(musicPlayerControllerProvider.notifier);
    final historyNotifier = ref.read(musicHistoryProvider.notifier);

    final connection = connections[track.sourceId];
    if (connection == null || connection.status != SourceStatus.connected) {
      logger.e('_playTrack: 源未连接 sourceId=${track.sourceId}');
      if (context.mounted) {
        context.showWarningToast('源未连接，请先连接到 NAS');
      }
      return;
    }

    try {
      logger.d('_playTrack: 获取文件URL, path=${track.path}');
      final url = await connection.adapter.fileSystem.getFileUrl(track.path);
      logger.d('_playTrack: 文件URL => $url');
      final musicItem = MusicItem.fromFileItem(
        track.file,
        url,
        sourceId: track.sourceId,
        // 传递预提取的元数据
        title: track.title,
        artist: track.artist,
        album: track.album,
        durationMs: track.duration,
        trackNumber: track.trackNumber,
        year: track.year,
        genre: track.genre,
        coverData: track.coverData,
        coverUrl: track.coverFileUrl,
      );

      // 找到当前曲目在列表中的索引
      final trackIndex = allTracks.indexWhere((t) => t.path == track.path);

      // 先播放当前曲目（使用提前获取的 notifier）
      playQueueNotifier.setQueue([musicItem]);
      playerNotifier.updateCurrentIndex(0);
      await playerNotifier.play(musicItem);

      // 记录最近播放
      await historyNotifier.addToHistory(musicItem);

      // 推荐列表不跳转到播放器页面，在顶部 HeroPlayerCard 播放即可

      // 在后台构建完整播放队列（使用提前获取的 notifier）
      AppError.fireAndForget(
        _buildPlayQueue(playQueueNotifier, playerNotifier, connections, track, allTracks, trackIndex),
        action: 'musicList.buildPlayQueue',
      );
    } on Exception catch (e) {
      if (context.mounted) {
        context.showErrorToast('播放失败: $e');
      }
    }
  }

  /// 在后台构建播放队列
  Future<void> _buildPlayQueue(
    PlayQueueNotifier playQueueNotifier,
    MusicPlayerNotifier playerNotifier,
    Map<String, SourceConnection> connections,
    MusicFileWithSource currentTrack,
    List<MusicFileWithSource> allTracks,
    int trackIndex,
  ) async {
    try {
      // 构建播放队列（最多50首，以当前曲目为中心）
      const queueSize = 50;
      int startIndex;
      int endIndex;

      if (allTracks.length <= queueSize) {
        startIndex = 0;
        endIndex = allTracks.length;
      } else {
        // 以当前曲目为中心
        final halfSize = queueSize ~/ 2;
        startIndex = (trackIndex - halfSize).clamp(0, allTracks.length - queueSize);
        endIndex = (startIndex + queueSize).clamp(0, allTracks.length);
      }

      final queueTracks = allTracks.sublist(startIndex, endIndex);
      final queue = <MusicItem>[];
      var newCurrentIndex = 0;

      for (var i = 0; i < queueTracks.length; i++) {
        final t = queueTracks[i];
        final conn = connections[t.sourceId];
        if (conn == null || conn.status != SourceStatus.connected) continue;
        final trackUrl = await conn.adapter.fileSystem.getFileUrl(t.path);
        final item = MusicItem.fromFileItem(
          t.file,
          trackUrl,
          sourceId: t.sourceId,
          // 传递预提取的元数据
          title: t.title,
          artist: t.artist,
          album: t.album,
          durationMs: t.duration,
          trackNumber: t.trackNumber,
          year: t.year,
          genre: t.genre,
          coverData: t.coverData,
          coverUrl: t.coverFileUrl,
        );
        queue.add(item);
        if (t.path == currentTrack.path) {
          newCurrentIndex = queue.length - 1;
        }
      }

      // 更新播放队列（使用传入的 notifier，不再使用 ref）
      playQueueNotifier.setQueue(queue);
      playerNotifier.updateCurrentIndex(newCurrentIndex);
    } on Exception catch (e) {
      logger.w('构建播放队列失败: $e');
    }
  }

  /// 随机播放
  Future<void> _shufflePlay(BuildContext context, WidgetRef ref, List<MusicFileWithSource> tracks) async {
    logger.i('MusicListPage._shufflePlay: 开始随机播放 (${tracks.length} 首)');

    if (tracks.isEmpty) {
      logger.w('MusicListPage._shufflePlay: 没有歌曲可播放');
      return;
    }

    final connections = ref.read(activeConnectionsProvider);
    final shuffled = List<MusicFileWithSource>.from(tracks)..shuffle();
    final first = shuffled.first;

    try {
      final firstConnection = connections[first.sourceId];
      if (firstConnection == null || firstConnection.status != SourceStatus.connected) {
        logger.e('MusicListPage._shufflePlay: 第一首歌曲的源未连接');
        if (context.mounted) {
          context.showWarningToast('源未连接，请先连接到 NAS');
        }
        return;
      }

      logger.d('MusicListPage._shufflePlay: 获取第一首歌曲 URL: ${first.path}');
      final url = await firstConnection.adapter.fileSystem.getFileUrl(first.path);
      final musicItem = MusicItem.fromFileItem(
        first.file,
        url,
        sourceId: first.sourceId,
        title: first.title,
        artist: first.artist,
        album: first.album,
        durationMs: first.duration,
        coverData: first.coverData,
        coverUrl: first.coverFileUrl,
      );

      final queue = <MusicItem>[];
      for (final track in shuffled.take(100)) {
        final conn = connections[track.sourceId];
        if (conn == null || conn.status != SourceStatus.connected) continue;
        final trackUrl = await conn.adapter.fileSystem.getFileUrl(track.path);
        queue.add(MusicItem.fromFileItem(
          track.file,
          trackUrl,
          sourceId: track.sourceId,
          title: track.title,
          artist: track.artist,
          album: track.album,
          durationMs: track.duration,
          coverData: track.coverData,
          coverUrl: track.coverFileUrl,
        ));
      }
      logger.d('MusicListPage._shufflePlay: 创建队列完成 (${queue.length} 首)');

      ref.read(playQueueProvider.notifier).setQueue(queue);
      await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);
      logger.i('MusicListPage._shufflePlay: 播放成功');

      if (context.mounted) {
        await MusicPlayerPage.open(context);
      }
    } on Exception catch (e, stackTrace) {
      logger.e('MusicListPage._shufflePlay: 播放失败', e, stackTrace);
      if (context.mounted) {
        context.showErrorToast('播放失败: $e');
      }
    }
  }

  Widget _buildLoadingState(
    BuildContext context,
    double progress,
    String? currentFolder,
    bool fromCache,
    List<MusicFileWithSource> partialTracks,
    int scannedCount,
    bool isDark,
  ) {
    // 如果有部分结果，显示带进度条的列表
    if (partialTracks.isNotEmpty && !fromCache) {
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
                        '正在扫描... 已找到 $scannedCount 首音乐',
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
          // 部分结果列表
          Expanded(
            child: ListView.builder(
              itemCount: partialTracks.length,
              itemBuilder: (context, index) {
                final track = partialTracks[index];
                return ListTile(
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.music_note_rounded,
                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                        ),
                        Positioned(
                          bottom: 2,
                          right: 2,
                          child: SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  title: Text(
                    track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white : null,
                    ),
                  ),
                  subtitle: Text(
                    '扫描中...',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[500] : Colors.grey[600],
                    ),
                  ),
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
            fromCache ? '加载缓存...' : '扫描音乐中...',
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
  }

  Widget _buildEmptyState(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
  ) {
    // 获取缓存信息
    final cacheService = MusicLibraryCacheService();
    final cacheInfo = cacheService.getCacheInfo();

    return Center(
      child: SingleChildScrollView(
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
                Icons.library_music_rounded,
                size: 50,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '音乐库为空',
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : null,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '请在媒体库设置中配置音乐目录并扫描',
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
}

// ==================== 新版首页组件 ====================

/// 音乐分类页面
class _MusicCategoryPage extends ConsumerWidget {
  const _MusicCategoryPage({
    required this.category,
  });

  final MusicCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return HideBottomNavWrapper(
      child: Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
        appBar: AppBar(
          title: Text(category.label),
          backgroundColor: isDark ? AppColors.darkSurface : null,
        ),
        body: Column(
          children: [
            Expanded(child: _buildContent(context, ref, isDark)),
            const MiniPlayer(),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, bool isDark) => switch (category) {
      // 这些分类视图现在直接从数据库获取全量数据
      MusicCategory.all => _AllSongsContent(tracks: const [], isDark: isDark), // 使用 provider 数据
      MusicCategory.artists => _ArtistsView(isDark: isDark),
      MusicCategory.albums => _AlbumsView(isDark: isDark),
      MusicCategory.folders => _FoldersView(isDark: isDark),
      MusicCategory.favorites => _FavoritesView(isDark: isDark),
      MusicCategory.recent => _RecentView(isDark: isDark),
      MusicCategory.genres => _GenresView(isDark: isDark),
      MusicCategory.years => _YearsView(isDark: isDark),
      MusicCategory.playlists => _PlaylistsView(isDark: isDark),
    };
}

/// 全部歌曲页面 - 独立的页面，支持更丰富的 AppBar
/// 从 provider 获取数据，支持无限滚动分页
class AllSongsPage extends ConsumerStatefulWidget {
  const AllSongsPage({
    this.tracks,
    super.key,
  });

  /// 可选的 tracks 参数（向后兼容），优先从 provider 获取
  final List<MusicFileWithSource>? tracks;

  @override
  ConsumerState<AllSongsPage> createState() => _AllSongsPageState();
}

class _AllSongsPageState extends ConsumerState<AllSongsPage>
    with ConsumerTabBarVisibilityMixin {
  final _scrollController = ScrollController();
  bool _isTableView = false; // 桌面端表格视图模式

  @override
  void initState() {
    super.initState();
    hideTabBar(); // 隐藏底部导航栏
    _scrollController.addListener(_onScroll);
    // 桌面端默认使用表格视图
    _isTableView = PlatformCapabilities.isDesktop;
  }

  @override
  void dispose() {
    _scrollController..removeListener(_onScroll)
    ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(musicListProvider.notifier).loadMoreTracks();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sortState = ref.watch(musicSortProvider);
    final musicState = ref.watch(musicListProvider);

    // 从 provider 获取数据
    final tracks = musicState is MusicListLoaded ? musicState.tracks : (widget.tracks ?? []);
    final totalCount = musicState is MusicListLoaded ? musicState.totalCount : tracks.length;
    final hasMore = musicState is MusicListLoaded && musicState.hasMoreTracks;
    final isLoadingMore = musicState is MusicListLoaded && musicState.isLoadingMore;

    final sortedTracks = _applySorting(tracks, sortState);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
      body: Column(
        children: [
          // 自定义顶栏
          _buildAppBar(context, isDark, sortState, totalCount),
          // 播放控制栏
          _buildPlayControls(context, isDark, sortedTracks),
          // 歌曲列表
          Expanded(
            child: tracks.isEmpty
                ? _buildEmptyState(isDark)
                : _isTableView && PlatformCapabilities.isDesktop
                    ? _buildTableView(context, sortedTracks, isDark, hasMore, isLoadingMore)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: sortedTracks.length + (hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= sortedTracks.length) {
                            return _buildLoadMoreIndicator(isDark, isLoadingMore);
                          }
                          return _ModernMusicTile(
                            track: sortedTracks[index],
                            index: index,
                            isDark: isDark,
                            allTracks: sortedTracks,
                          );
                        },
                      ),
          ),
          const MiniPlayer(),
        ],
      ),
    );
  }

  Widget _buildLoadMoreIndicator(bool isDark, bool isLoading) => Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      alignment: Alignment.center,
      child: isLoading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              '上拉加载更多',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
    );

  Widget _buildAppBar(BuildContext context, bool isDark, MusicSortState sortState, int trackCount) {
    final uiStyle = ref.watch(uiStyleProvider);

    return AdaptiveGlassHeader(
      height: 56,
      backgroundColor: uiStyle.isGlass
          ? (isDark
              ? Colors.deepOrange.withValues(alpha: 0.1)
              : Colors.deepOrange.withValues(alpha: 0.05))
          : (isDark ? AppColors.darkSurface : Colors.white),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          4,
          AppSpacing.appBarVerticalPadding,
          AppSpacing.appBarHorizontalPadding,
          12,
        ),
        child: Row(
          children: [
            // 返回按钮
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(
                Icons.arrow_back_rounded,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            // 标题和歌曲数量
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      flex: 0,
                      child: Text(
                        '所有歌曲',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                          height: 1.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Flexible(
                      flex: 0,
                      child: Text(
                        '共 $trackCount 首',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                          height: 1.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 视图切换按钮（仅桌面端显示）
            if (PlatformCapabilities.isDesktop) ...[
              IconButton(
                onPressed: () => setState(() => _isTableView = !_isTableView),
                icon: Icon(
                  _isTableView ? Icons.grid_view_rounded : Icons.table_rows_rounded,
                  color: isDark ? Colors.white70 : Colors.black54,
                  size: 20,
                ),
                tooltip: _isTableView ? '网格视图' : '表格视图',
              ),
            ],
            // 排序按钮
            _SortButton(
              sortState: sortState,
              isDark: isDark,
              onTap: () => _showSortOptions(context, sortState, isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayControls(BuildContext context, bool isDark, List<MusicFileWithSource> sortedTracks) {
    if (sortedTracks.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          // 播放全部按钮
          Expanded(
            child: _SpotifyPlayButton(
              onPressed: () => _playAll(context, sortedTracks),
              icon: Icons.play_arrow_rounded,
              label: '播放全部',
            ),
          ),
          const SizedBox(width: 12),
          // 随机播放按钮
          Expanded(
            child: _SpotifyPlayButton(
              onPressed: () => _shufflePlay(context, sortedTracks),
              icon: Icons.shuffle_rounded,
              label: '随机播放',
              isPrimary: false,
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.2),
                  AppColors.secondary.withValues(alpha: 0.2),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.music_off_rounded, size: 40, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无歌曲',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '扫描音乐库以添加歌曲',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey[600] : Colors.grey[500],
            ),
          ),
        ],
      ),
    );

  /// 桌面端表格视图
  Widget _buildTableView(
    BuildContext context,
    List<MusicFileWithSource> tracks,
    bool isDark,
    bool hasMore,
    bool isLoadingMore,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // 表头
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
            border: Border(
              bottom: BorderSide(
                color: isDark ? Colors.white12 : Colors.black12,
              ),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 40), // 序号列
              const Expanded(flex: 4, child: _TableHeader(title: '标题')),
              const Expanded(flex: 2, child: _TableHeader(title: '艺术家')),
              const Expanded(flex: 2, child: _TableHeader(title: '专辑')),
              const SizedBox(width: 60, child: _TableHeader(title: '时长', align: TextAlign.right)),
              const SizedBox(width: 48), // 操作列
            ],
          ),
        ),
        // 数据行
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: tracks.length + (hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= tracks.length) {
                return _buildLoadMoreIndicator(isDark, isLoadingMore);
              }

              final track = tracks[index];
              final isEven = index.isEven;

              return _MusicTableRow(
                track: track,
                index: index,
                isDark: isDark,
                isEven: isEven,
                allTracks: tracks,
                colorScheme: colorScheme,
              );
            },
          ),
        ),
      ],
    );
  }

  List<MusicFileWithSource> _applySorting(
    List<MusicFileWithSource> tracks,
    MusicSortState sortState,
  ) {
    final sorted = List<MusicFileWithSource>.from(tracks)
      ..sort((a, b) {
        int result;
        switch (sortState.option) {
          case MusicSortOption.name:
            result = a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
          case MusicSortOption.artist:
            result = a.displayArtist.toLowerCase().compareTo(b.displayArtist.toLowerCase());
          case MusicSortOption.album:
            result = a.displayAlbum.toLowerCase().compareTo(b.displayAlbum.toLowerCase());
          case MusicSortOption.dateAdded:
            final aTime = a.modifiedTime ?? DateTime(1970);
            final bTime = b.modifiedTime ?? DateTime(1970);
            result = aTime.compareTo(bTime);
          case MusicSortOption.duration:
            result = (a.duration ?? 0).compareTo(b.duration ?? 0);
        }
        return sortState.direction == SortDirection.ascending ? result : -result;
      });

    return sorted;
  }

  void _showSortOptions(BuildContext context, MusicSortState currentSort, bool isDark) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖动指示器
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkOutline : AppColors.lightOutline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 标题
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.swap_vert_rounded,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '排序方式',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  // 排序方向切换
                  _SortDirectionButton(
                    direction: currentSort.direction,
                    isDark: isDark,
                    onTap: () {
                      final newDirection = currentSort.direction == SortDirection.ascending
                          ? SortDirection.descending
                          : SortDirection.ascending;
                      ref.read(musicSortProvider.notifier).state = currentSort.copyWith(
                        direction: newDirection,
                      );
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 排序选项列表
            ...MusicSortOption.values.map((option) => _SortOptionTile(
              option: option,
              isSelected: currentSort.option == option,
              isDark: isDark,
              onTap: () {
                ref.read(musicSortProvider.notifier).state = currentSort.copyWith(
                  option: option,
                );
                Navigator.pop(context);
              },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _playAll(BuildContext context, List<MusicFileWithSource> sortedTracks) async {
    logger.i('AllSongsPage._playAll: 开始播放全部 (${sortedTracks.length} 首)');

    if (sortedTracks.isEmpty) {
      logger.w('AllSongsPage._playAll: 没有歌曲可播放');
      return;
    }

    final connections = ref.read(activeConnectionsProvider);

    try {
      final first = sortedTracks.first;
      final firstConnection = connections[first.sourceId];
      if (firstConnection == null || firstConnection.status != SourceStatus.connected) {
        logger.e('AllSongsPage._playAll: 第一首歌曲的源未连接');
        if (context.mounted) {
          context.showWarningToast('源未连接，请先连接到 NAS');
        }
        return;
      }

      logger.d('AllSongsPage._playAll: 获取第一首歌曲 URL: ${first.path}');
      final url = await firstConnection.adapter.fileSystem.getFileUrl(first.path);
      final musicItem = MusicItem.fromFileItem(
        first.file,
        url,
        sourceId: first.sourceId,
        title: first.title,
        artist: first.artist,
        album: first.album,
        durationMs: first.duration,
        coverData: first.coverData,
        coverUrl: first.coverFileUrl,
      );

      final queue = <MusicItem>[];
      for (final track in sortedTracks.take(100)) {
        final conn = connections[track.sourceId];
        if (conn == null || conn.status != SourceStatus.connected) continue;
        final trackUrl = await conn.adapter.fileSystem.getFileUrl(track.path);
        queue.add(MusicItem.fromFileItem(
          track.file,
          trackUrl,
          sourceId: track.sourceId,
          title: track.title,
          artist: track.artist,
          album: track.album,
          durationMs: track.duration,
          coverData: track.coverData,
          coverUrl: track.coverFileUrl,
        ));
      }
      logger.d('AllSongsPage._playAll: 创建队列完成 (${queue.length} 首)');

      ref.read(playQueueProvider.notifier).setQueue(queue);
      await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);
      logger.i('AllSongsPage._playAll: 播放成功');

      if (context.mounted) {
        await MusicPlayerPage.open(context);
      }
    } on Exception catch (e, stackTrace) {
      logger.e('AllSongsPage._playAll: 播放失败', e, stackTrace);
      if (context.mounted) {
        context.showErrorToast('播放失败: $e');
      }
    }
  }

  Future<void> _shufflePlay(BuildContext context, List<MusicFileWithSource> sortedTracks) async {
    logger.i('AllSongsPage._shufflePlay: 开始随机播放 (${sortedTracks.length} 首)');

    if (sortedTracks.isEmpty) {
      logger.w('AllSongsPage._shufflePlay: 没有歌曲可播放');
      return;
    }

    final connections = ref.read(activeConnectionsProvider);
    final shuffled = List<MusicFileWithSource>.from(sortedTracks)..shuffle();
    final first = shuffled.first;

    try {
      final firstConnection = connections[first.sourceId];
      if (firstConnection == null || firstConnection.status != SourceStatus.connected) {
        logger.e('AllSongsPage._shufflePlay: 第一首歌曲的源未连接');
        if (context.mounted) {
          context.showWarningToast('源未连接，请先连接到 NAS');
        }
        return;
      }

      logger.d('AllSongsPage._shufflePlay: 获取第一首歌曲 URL: ${first.path}');
      final url = await firstConnection.adapter.fileSystem.getFileUrl(first.path);
      final musicItem = MusicItem.fromFileItem(
        first.file,
        url,
        sourceId: first.sourceId,
        title: first.title,
        artist: first.artist,
        album: first.album,
        durationMs: first.duration,
        coverData: first.coverData,
        coverUrl: first.coverFileUrl,
      );

      final queue = <MusicItem>[];
      for (final track in shuffled.take(100)) {
        final conn = connections[track.sourceId];
        if (conn == null || conn.status != SourceStatus.connected) continue;
        final trackUrl = await conn.adapter.fileSystem.getFileUrl(track.path);
        queue.add(MusicItem.fromFileItem(
          track.file,
          trackUrl,
          sourceId: track.sourceId,
          title: track.title,
          artist: track.artist,
          album: track.album,
          durationMs: track.duration,
          coverData: track.coverData,
          coverUrl: track.coverFileUrl,
        ));
      }
      logger.d('AllSongsPage._shufflePlay: 创建队列完成 (${queue.length} 首)');

      ref.read(playQueueProvider.notifier).setQueue(queue);
      await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);
      logger.i('AllSongsPage._shufflePlay: 播放成功');

      if (context.mounted) {
        await MusicPlayerPage.open(context);
      }
    } on Exception catch (e, stackTrace) {
      logger.e('AllSongsPage._shufflePlay: 播放失败', e, stackTrace);
      if (context.mounted) {
        context.showErrorToast('播放失败: $e');
      }
    }
  }
}

/// 排序按钮组件
class _SortButton extends StatelessWidget {
  const _SortButton({
    required this.sortState,
    required this.isDark,
    required this.onTap,
  });

  final MusicSortState sortState;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                sortState.direction == SortDirection.ascending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: 4),
              Text(
                sortState.option.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
}

/// 全部歌曲内容（用于嵌入到通用分类页面中）
class _AllSongsContent extends ConsumerStatefulWidget {
  const _AllSongsContent({
    required this.tracks,
    required this.isDark,
  });

  final List<MusicFileWithSource> tracks;
  final bool isDark;

  @override
  ConsumerState<_AllSongsContent> createState() => _AllSongsContentState();
}

class _AllSongsContentState extends ConsumerState<_AllSongsContent> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController..removeListener(_onScroll)
    ..dispose();
    super.dispose();
  }

  void _onScroll() {
    // 当滚动到距离底部 200 像素时触发加载更多
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(musicListProvider.notifier).loadMoreTracks();
    }
  }

  @override
  Widget build(BuildContext context) {
    final musicState = ref.watch(musicListProvider);
    final totalCount = musicState is MusicListLoaded ? musicState.totalCount : 0;
    final hasMore = musicState is MusicListLoaded && musicState.hasMoreTracks;
    final isLoadingMore = musicState is MusicListLoaded && musicState.isLoadingMore;

    if (widget.tracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.2),
                    AppColors.secondary.withValues(alpha: 0.2),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.music_off_rounded, size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              '暂无歌曲',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: widget.isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '扫描音乐库以添加歌曲',
              style: TextStyle(
                fontSize: 13,
                color: widget.isDark ? Colors.grey[600] : Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    // 应用排序
    final sortState = ref.watch(musicSortProvider);
    final sortedTracks = _applySorting(widget.tracks, sortState);

    // 计算需要显示的项目数（包括加载更多指示器）
    final itemCount = sortedTracks.length + (hasMore ? 1 : 0);

    return Column(
      children: [
        // 播放控制栏 - 显示总数而不是当前加载数
        _buildControlBar(context, ref, sortState, totalCount),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: itemCount,
            itemBuilder: (context, index) {
              // 最后一项显示加载更多指示器
              if (index >= sortedTracks.length) {
                return _buildLoadMoreIndicator(isLoadingMore);
              }
              return _ModernMusicTile(
                track: sortedTracks[index],
                index: index,
                isDark: widget.isDark,
                allTracks: sortedTracks,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLoadMoreIndicator(bool isLoading) => Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      alignment: Alignment.center,
      child: isLoading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              '上拉加载更多',
              style: TextStyle(
                fontSize: 13,
                color: widget.isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
    );

  List<MusicFileWithSource> _applySorting(
    List<MusicFileWithSource> tracks,
    MusicSortState sortState,
  ) {
    final sorted = List<MusicFileWithSource>.from(tracks)
      ..sort((a, b) {
        int result;
        switch (sortState.option) {
          case MusicSortOption.name:
            result = a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
          case MusicSortOption.artist:
            result = a.displayArtist.toLowerCase().compareTo(b.displayArtist.toLowerCase());
          case MusicSortOption.album:
            result = a.displayAlbum.toLowerCase().compareTo(b.displayAlbum.toLowerCase());
          case MusicSortOption.dateAdded:
            final aTime = a.modifiedTime ?? DateTime(1970);
            final bTime = b.modifiedTime ?? DateTime(1970);
            result = aTime.compareTo(bTime);
          case MusicSortOption.duration:
            result = (a.duration ?? 0).compareTo(b.duration ?? 0);
        }
        return sortState.direction == SortDirection.ascending ? result : -result;
      });

    return sorted;
  }

  Widget _buildControlBar(BuildContext context, WidgetRef ref, MusicSortState sortState, int totalCount) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部信息行：歌曲数量 + 排序按钮
          Row(
            children: [
              // 歌曲数量 - 使用数据库总数而不是当前加载的数量
              Text(
                '共 $totalCount 首歌曲',
                style: TextStyle(
                  fontSize: 13,
                  color: widget.isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              const Spacer(),
              // 排序按钮
              _SpotifyIconButton(
                icon: Icons.swap_vert_rounded,
                label: sortState.option.label,
                isDark: widget.isDark,
                onTap: () => _showSortOptions(context, ref, sortState),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 播放按钮行
          Row(
            children: [
              // 播放全部按钮
              Expanded(
                child: _SpotifyPlayButton(
                  onPressed: () => _playAll(context, ref),
                  icon: Icons.play_arrow_rounded,
                  label: '播放全部',
                ),
              ),
              const SizedBox(width: 12),
              // 随机播放按钮
              Expanded(
                child: _SpotifyPlayButton(
                  onPressed: () => _shufflePlay(context, ref),
                  icon: Icons.shuffle_rounded,
                  label: '随机播放',
                  isPrimary: false,
                  isDark: widget.isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );

  void _showSortOptions(BuildContext context, WidgetRef ref, MusicSortState currentSort) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: widget.isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖动指示器
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: widget.isDark ? AppColors.darkOutline : AppColors.lightOutline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 标题
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.swap_vert_rounded,
                    color: widget.isDark ? Colors.white70 : Colors.black87,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '排序方式',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: widget.isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  // 排序方向切换
                  _SortDirectionButton(
                    direction: currentSort.direction,
                    isDark: widget.isDark,
                    onTap: () {
                      final newDirection = currentSort.direction == SortDirection.ascending
                          ? SortDirection.descending
                          : SortDirection.ascending;
                      ref.read(musicSortProvider.notifier).state = currentSort.copyWith(
                        direction: newDirection,
                      );
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 排序选项列表
            ...MusicSortOption.values.map((option) => _SortOptionTile(
              option: option,
              isSelected: currentSort.option == option,
              isDark: widget.isDark,
              onTap: () {
                ref.read(musicSortProvider.notifier).state = currentSort.copyWith(
                  option: option,
                );
                Navigator.pop(context);
              },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _playAll(BuildContext context, WidgetRef ref) async {
    logger.i('_AllSongsView._playAll: 开始播放全部 (${widget.tracks.length} 首)');

    if (widget.tracks.isEmpty) {
      logger.w('_AllSongsView._playAll: 没有歌曲可播放');
      return;
    }

    final connections = ref.read(activeConnectionsProvider);

    try {
      final first = widget.tracks.first;
      final firstConnection = connections[first.sourceId];
      if (firstConnection == null || firstConnection.status != SourceStatus.connected) {
        logger.e('_AllSongsView._playAll: 第一首歌曲的源未连接');
        if (context.mounted) {
          context.showWarningToast('源未连接，请先连接到 NAS');
        }
        return;
      }

      logger.d('_AllSongsView._playAll: 获取第一首歌曲 URL: ${first.path}');
      final url = await firstConnection.adapter.fileSystem.getFileUrl(first.path);
      final musicItem = MusicItem.fromFileItem(
        first.file,
        url,
        sourceId: first.sourceId,
        title: first.title,
        artist: first.artist,
        album: first.album,
        durationMs: first.duration,
        coverData: first.coverData,
        coverUrl: first.coverFileUrl,
      );

      final queue = <MusicItem>[];
      for (final track in widget.tracks.take(100)) {
        final conn = connections[track.sourceId];
        if (conn == null || conn.status != SourceStatus.connected) continue;
        final trackUrl = await conn.adapter.fileSystem.getFileUrl(track.path);
        queue.add(MusicItem.fromFileItem(
          track.file,
          trackUrl,
          sourceId: track.sourceId,
          title: track.title,
          artist: track.artist,
          album: track.album,
          durationMs: track.duration,
          coverData: track.coverData,
          coverUrl: track.coverFileUrl,
        ));
      }
      logger.d('_AllSongsView._playAll: 创建队列完成 (${queue.length} 首)');

      ref.read(playQueueProvider.notifier).setQueue(queue);
      await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);
      logger.i('_AllSongsView._playAll: 播放成功');

      if (context.mounted) {
        await MusicPlayerPage.open(context);
      }
    } on Exception catch (e, stackTrace) {
      logger.e('_AllSongsView._playAll: 播放失败', e, stackTrace);
      if (context.mounted) {
        context.showErrorToast('播放失败: $e');
      }
    }
  }

  Future<void> _shufflePlay(BuildContext context, WidgetRef ref) async {
    logger.i('_AllSongsView._shufflePlay: 开始随机播放 (${widget.tracks.length} 首)');

    if (widget.tracks.isEmpty) {
      logger.w('_AllSongsView._shufflePlay: 没有歌曲可播放');
      return;
    }

    final connections = ref.read(activeConnectionsProvider);
    final shuffled = List<MusicFileWithSource>.from(widget.tracks)..shuffle();
    final first = shuffled.first;

    try {
      final firstConnection = connections[first.sourceId];
      if (firstConnection == null || firstConnection.status != SourceStatus.connected) {
        logger.e('_AllSongsView._shufflePlay: 第一首歌曲的源未连接');
        if (context.mounted) {
          context.showWarningToast('源未连接，请先连接到 NAS');
        }
        return;
      }

      logger.d('_AllSongsView._shufflePlay: 获取第一首歌曲 URL: ${first.path}');
      final url = await firstConnection.adapter.fileSystem.getFileUrl(first.path);
      final musicItem = MusicItem.fromFileItem(
        first.file,
        url,
        sourceId: first.sourceId,
        title: first.title,
        artist: first.artist,
        album: first.album,
        durationMs: first.duration,
        coverData: first.coverData,
        coverUrl: first.coverFileUrl,
      );

      final queue = <MusicItem>[];
      for (final track in shuffled.take(100)) {
        final conn = connections[track.sourceId];
        if (conn == null || conn.status != SourceStatus.connected) continue;
        final trackUrl = await conn.adapter.fileSystem.getFileUrl(track.path);
        queue.add(MusicItem.fromFileItem(
          track.file,
          trackUrl,
          sourceId: track.sourceId,
          title: track.title,
          artist: track.artist,
          album: track.album,
          durationMs: track.duration,
          coverData: track.coverData,
          coverUrl: track.coverFileUrl,
        ));
      }
      logger.d('_AllSongsView._shufflePlay: 创建队列完成 (${queue.length} 首)');

      ref.read(playQueueProvider.notifier).setQueue(queue);
      await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);
      logger.i('_AllSongsView._shufflePlay: 播放成功');

      if (context.mounted) {
        await MusicPlayerPage.open(context);
      }
    } on Exception catch (e, stackTrace) {
      logger.e('_AllSongsView._shufflePlay: 播放失败', e, stackTrace);
      if (context.mounted) {
        context.showErrorToast('播放失败: $e');
      }
    }
  }
}

class _MusicListTile extends ConsumerWidget {
  const _MusicListTile({
    required this.track,
    required this.index,
    required this.isDark,
  });

  final MusicFileWithSource track;
  final int index;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(currentMusicProvider);
    final isPlaying = currentMusic?.path == track.path;

    // 使用元数据（如已提取）或从文件名解析
    final title = track.displayTitle;
    final artist = track.displayArtist;

    // 根据索引生成渐变色
    final gradientColors = _getGradientColorsForIndex(index);

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isPlaying
            ? AppColors.fileAudio.withValues(alpha: isDark ? 0.15 : 0.1)
            : (isDark
                ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
                : context.colorScheme.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPlaying
              ? AppColors.fileAudio.withValues(alpha: 0.3)
              : (isDark
                  ? AppColors.darkOutline.withValues(alpha: 0.15)
                  : context.colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _playTrack(context, ref),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // 序号
                SizedBox(
                  width: 28,
                  child: isPlaying
                      ? Icon(
                          Icons.equalizer_rounded,
                          color: AppColors.fileAudio,
                          size: 18,
                        )
                      : Text(
                          '${index + 1}',
                          textAlign: TextAlign.center,
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: isDark
                                ? AppColors.darkOnSurfaceVariant
                                : context.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                // 封面
                _buildCoverWidget(
                  context,
                  title: title,
                  isPlaying: isPlaying,
                  gradientColors: gradientColors,
                ),
                const SizedBox(width: 12),
                // 标题和艺术家
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: isPlaying
                              ? AppColors.fileAudio
                              : (isDark ? AppColors.darkOnSurface : null),
                          fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textTheme.bodySmall?.copyWith(
                                color: isDark
                                    ? AppColors.darkOnSurfaceVariant
                                    : context.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (track.duration != null) ...[
                            Text(
                              ' · ',
                              style: context.textTheme.bodySmall?.copyWith(
                                color: isDark
                                    ? AppColors.darkOnSurfaceVariant
                                    : context.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              track.durationText,
                              style: context.textTheme.bodySmall?.copyWith(
                                color: isDark
                                    ? AppColors.darkOnSurfaceVariant
                                    : context.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // 文件大小标签
                if (track.metadataExtracted)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isDark
                              ? AppColors.darkSurfaceElevated
                              : context.colorScheme.surfaceContainerHighest)
                          .withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      track.displaySize,
                      style: context.textTheme.labelSmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : context.colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  ),
                PopupMenuButton<String>(
                  onSelected: (value) => _handleMenuAction(context, ref, value),
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: isDark ? AppColors.darkOnSurfaceVariant : null,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  color: isDark ? AppColors.darkSurface : null,
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'play_next',
                      child: Row(
                        children: [
                          Icon(
                            Icons.queue_play_next_rounded,
                            color: isDark ? AppColors.darkOnSurface : null,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '下一首播放',
                            style: TextStyle(
                              color: isDark ? AppColors.darkOnSurface : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'add_to_queue',
                      child: Row(
                        children: [
                          Icon(
                            Icons.playlist_add_rounded,
                            color: isDark ? AppColors.darkOnSurface : null,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '添加到播放列表',
                            style: TextStyle(
                              color: isDark ? AppColors.darkOnSurface : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'add_to_favorites',
                      child: Row(
                        children: [
                          Icon(
                            Icons.favorite_border_rounded,
                            color: isDark ? AppColors.darkOnSurface : null,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '收藏',
                            style: TextStyle(
                              color: isDark ? AppColors.darkOnSurface : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'add_to_playlist',
                      child: Row(
                        children: [
                          Icon(
                            Icons.playlist_add_rounded,
                            color: isDark ? AppColors.darkOnSurface : null,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '添加到歌单',
                            style: TextStyle(
                              color: isDark ? AppColors.darkOnSurface : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'manual_scrape',
                      child: Row(
                        children: [
                          Icon(
                            Icons.search_rounded,
                            color: isDark ? AppColors.darkOnSurface : null,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '手动刮削',
                            style: TextStyle(
                              color: isDark ? AppColors.darkOnSurface : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'remove_from_library',
                      child: Row(
                        children: [
                          Icon(
                            Icons.visibility_off_rounded,
                            color: isDark ? AppColors.darkOnSurface : null,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '从媒体库移除',
                            style: TextStyle(
                              color: isDark ? AppColors.darkOnSurface : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete_from_source',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_forever_rounded,
                            color: AppColors.error,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '删除源文件',
                            style: TextStyle(
                              color: AppColors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建封面组件
  Widget _buildCoverWidget(
    BuildContext context, {
    required String title,
    required bool isPlaying,
    required List<Color> gradientColors,
  }) {
    final coverFile = track.coverFile;
    final coverData = track.coverData;
    final hasCover = coverFile != null || coverData != null;

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: !hasCover
            ? LinearGradient(
                colors: isPlaying
                    ? [AppColors.fileAudio, AppColors.secondary]
                    : gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        boxShadow: isPlaying
            ? [
                BoxShadow(
                  color: AppColors.fileAudio.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: coverFile != null
          ? Image.file(
              coverFile,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) => _buildFallbackCover(title),
            )
          : coverData != null
              ? Image.memory(
                  Uint8List.fromList(coverData),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) => _buildFallbackCover(title),
                )
              : _buildFallbackCover(title),
    );
  }

  Widget _buildFallbackCover(String title) => Center(
      child: Text(
        title.isNotEmpty ? title[0].toUpperCase() : '♪',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

  Future<void> _playTrack(BuildContext context, WidgetRef ref) async {
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[track.sourceId];
    if (connection == null || connection.status != SourceStatus.connected) {
      if (context.mounted) {
        context.showWarningToast('源未连接，请先连接到 NAS');
      }
      return;
    }

    final url = await connection.adapter.fileSystem.getFileUrl(track.path);
    final musicItem = MusicItem.fromFileItem(
      track.file,
      url,
      sourceId: track.sourceId,
      title: track.title,
      artist: track.artist,
      album: track.album,
      durationMs: track.duration,
      trackNumber: track.trackNumber,
      year: track.year,
      genre: track.genre,
      coverData: track.coverData,
      coverUrl: track.coverFileUrl,
    );

    if (!context.mounted) return;

    await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);

    if (!context.mounted) return;
    await MusicPlayerPage.open(context);
  }

  Future<void> _handleMenuAction(BuildContext context, WidgetRef ref, String action) async {
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[track.sourceId];
    if (connection == null || connection.status != SourceStatus.connected) {
      if (context.mounted) {
        context.showWarningToast('源未连接，请先连接到 NAS');
      }
      return;
    }

    final url = await connection.adapter.fileSystem.getFileUrl(track.path);
    final musicItem = MusicItem.fromFileItem(
      track.file,
      url,
      sourceId: track.sourceId,
      title: track.title,
      artist: track.artist,
      album: track.album,
      durationMs: track.duration,
      trackNumber: track.trackNumber,
      year: track.year,
      genre: track.genre,
      coverData: track.coverData,
      coverUrl: track.coverFileUrl,
    );

    switch (action) {
      case 'play_next':
        final queue = ref.read(playQueueProvider);
        final playerState = ref.read(musicPlayerControllerProvider);

        if (queue.isEmpty) {
          await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);
        } else {
          final insertIndex = playerState.currentIndex + 1;
          final newQueue = [...queue];
          newQueue.insert(insertIndex.clamp(0, newQueue.length), musicItem);
          ref.read(playQueueProvider.notifier).setQueue(newQueue);

          if (context.mounted) {
            context.showSuccessToast('已添加到下一首播放');
          }
        }

      case 'add_to_queue':
        ref.read(playQueueProvider.notifier).addToQueue(musicItem);
        if (context.mounted) {
          context.showSuccessToast('已添加到播放队列');
        }

      case 'add_to_favorites':
        final isFav = await ref.read(musicFavoritesProvider.notifier).toggleFavorite(musicItem);
        if (context.mounted) {
          context.showSuccessToast(isFav ? '已添加到收藏' : '已取消收藏');
        }

      case 'add_to_playlist':
        if (context.mounted) {
          // 使用 sourceId_path 格式唯一标识歌曲
          final trackId = '${track.sourceId}_${track.path}';
          _showAddToPlaylistDialog(context, ref, trackId);
        }

      case 'remove_from_library':
        if (context.mounted) {
          final confirmed = await showDeleteConfirmDialog(
            context: context,
            title: '从媒体库移除',
            content: '确定要从媒体库移除「${track.displayTitle}」吗？\n\n这只会移除索引记录，源文件不会被删除。',
            confirmText: '移除',
            isDestructive: false,
          );
          if (confirmed && context.mounted) {
            final success = await ref.read(musicListProvider.notifier).removeFromLibrary(
              track.sourceId,
              track.path,
              track.displayTitle,
            );
            if (context.mounted) {
              context.showSuccessToast(success ? '已从媒体库移除' : '移除失败');
            }
          }
        }

      case 'delete_from_source':
        if (context.mounted) {
          final confirmed = await showDeleteConfirmDialog(
            context: context,
            title: '删除源文件',
            content: '确定要删除「${track.displayTitle}」的源文件吗？\n\n⚠️ 此操作不可恢复！文件将从 NAS 中永久删除。',
          );
          if (confirmed && context.mounted) {
            final success = await ref.read(musicListProvider.notifier).deleteFromSource(
              track.sourceId,
              track.path,
              track.displayTitle,
            );
            if (context.mounted) {
              context.showSuccessToast(success ? '已删除源文件' : '删除失败，请检查连接状态');
            }
          }
        }

      case 'manual_scrape':
        if (context.mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ManualMusicScraperPage(
                music: musicItem,
                fileSystem: connection.adapter.fileSystem,
              ),
            ),
          );
        }
    }
  }

  void _showAddToPlaylistDialog(BuildContext context, WidgetRef ref, String trackPath) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final playlistState = ref.read(playlistProvider);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '添加到歌单',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            // 新建歌单选项
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.add_rounded, color: AppColors.primary),
              ),
              title: Text(
                '新建歌单',
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
              onTap: () {
                Navigator.pop(context);
                _showCreateAndAddDialog(context, ref, trackPath);
              },
            ),
            // 已有歌单列表
            if (playlistState.playlists.isNotEmpty) ...[
              const Divider(),
              ...playlistState.playlists.take(5).map((playlist) => ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.7),
                          AppColors.secondary.withValues(alpha: 0.7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.queue_music_rounded, color: Colors.white, size: 20),
                  ),
                  title: Text(
                    playlist.name,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  ),
                  subtitle: Text(
                    '${playlist.trackCount} 首歌曲',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                    ),
                  ),
                  onTap: () async {
                    await ref.read(playlistProvider.notifier).addToPlaylist(playlist.id, trackPath);
                    if (context.mounted) {
                      Navigator.pop(context);
                      context.showSuccessToast('已添加到歌单"${playlist.name}"');
                    }
                  },
                )),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showCreateAndAddDialog(BuildContext context, WidgetRef ref, String trackPath) {
    final controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        title: Text(
          '新建歌单',
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '输入歌单名称',
            hintStyle: TextStyle(
              color: isDark ? Colors.grey[500] : Colors.grey[400],
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                final playlist = await ref
                    .read(playlistProvider.notifier)
                    .createPlaylist(name: name, initialTracks: [trackPath]);
                if (context.mounted && playlist != null) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已添加到新歌单"$name"'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('创建并添加'),
          ),
        ],
      ),
    );
  }
}

/// 分类详情页 - 通用的音乐列表页面
/// 用于显示艺术家、流派、年代、文件夹下的所有歌曲
class CategoryDetailPage extends ConsumerStatefulWidget {
  const CategoryDetailPage({
    required this.title,
    required this.subtitle,
    required this.tracks,
    required this.icon,
    required this.color,
    this.coverWidget,
    super.key,
  });

  final String title;
  final String subtitle;
  final List<MusicFileWithSource> tracks;
  final IconData icon;
  final Color color;
  final Widget? coverWidget;

  @override
  ConsumerState<CategoryDetailPage> createState() => _CategoryDetailPageState();
}

class _CategoryDetailPageState extends ConsumerState<CategoryDetailPage>
    with ConsumerTabBarVisibilityMixin {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    hideTabBar(); // 隐藏底部导航栏
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uiStyle = ref.watch(uiStyleProvider);
    final safeTop = MediaQuery.of(context).padding.top;
    final bgColor = isDark ? AppColors.darkBackground : Colors.grey[50];

    // iOS 26 玻璃模式
    if (uiStyle.isGlass) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Stack(
          children: [
            Column(
              children: [
                // 顶部区域（使用渐变背景）
                _buildGlassHeader(context, isDark, safeTop),
                // 播放控制
                _buildPlayControls(context, isDark),
                // 歌曲列表
                Expanded(
                  child: widget.tracks.isEmpty
                      ? _buildEmptyState(isDark)
                      : ListView.builder(
                          controller: _scrollController,
                          padding: EdgeInsets.only(bottom: context.scrollBottomPadding),
                          itemCount: widget.tracks.length,
                          itemBuilder: (context, index) => _ModernMusicTile(
                            track: widget.tracks[index],
                            index: index,
                            isDark: isDark,
                            allTracks: widget.tracks,
                          ),
                        ),
                ),
                const MiniPlayer(),
              ],
            ),
            // 悬浮返回按钮
            Positioned(
              top: safeTop + 8,
              left: 16,
              child: const GlassFloatingBackButton(),
            ),
          ],
        ),
      );
    }

    // 经典模式
    return Scaffold(
      backgroundColor: bgColor,
      body: Column(
        children: [
          // 顶部区域
          _buildHeader(context, isDark),
          // 播放控制
          _buildPlayControls(context, isDark),
          // 歌曲列表
          Expanded(
            child: widget.tracks.isEmpty
                ? _buildEmptyState(isDark)
                : ListView.builder(
                    controller: _scrollController,
                    // 使用动态 padding 支持悬浮导航栏
                    padding: EdgeInsets.only(bottom: context.scrollBottomPadding),
                    itemCount: widget.tracks.length,
                    itemBuilder: (context, index) => _ModernMusicTile(
                      track: widget.tracks[index],
                      index: index,
                      isDark: isDark,
                      allTracks: widget.tracks,
                    ),
                  ),
          ),
          const MiniPlayer(),
        ],
      ),
    );
  }

  /// 玻璃模式下的头部（无返回按钮，返回按钮悬浮在外层）
  Widget _buildGlassHeader(BuildContext context, bool isDark, double safeTop) => DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            widget.color.withValues(alpha: isDark ? 0.3 : 0.15),
            isDark ? AppColors.darkBackground : Colors.grey[50]!,
          ],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, safeTop + 56, 16, 16),
        child: Row(
          children: [
            // 图标/封面
            widget.coverWidget ??
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        widget.color,
                        widget.color.withValues(alpha: 0.6),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    widget.icon,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
            const SizedBox(width: 16),
            // 标题信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

  Widget _buildHeader(BuildContext context, bool isDark) => DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            widget.color.withValues(alpha: isDark ? 0.3 : 0.15),
            isDark ? AppColors.darkBackground : Colors.grey[50]!,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 16, 16),
          child: Column(
            children: [
              // 返回按钮行
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 8),
              // 信息卡片
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    // 图标/封面
                    widget.coverWidget ??
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                widget.color,
                                widget.color.withValues(alpha: 0.6),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: widget.color.withValues(alpha: 0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            widget.icon,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                    const SizedBox(width: 16),
                    // 标题信息
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.subtitle,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

  Widget _buildPlayControls(BuildContext context, bool isDark) {
    if (widget.tracks.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: _SpotifyPlayButton(
              onPressed: () => _playAll(context),
              icon: Icons.play_arrow_rounded,
              label: '播放全部',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _SpotifyPlayButton(
              onPressed: () => _shufflePlay(context),
              icon: Icons.shuffle_rounded,
              label: '随机播放',
              isPrimary: false,
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.icon,
            size: 64,
            color: isDark ? Colors.grey[700] : Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            '暂无歌曲',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.grey[500] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );

  Future<void> _playAll(BuildContext context) async {
    if (widget.tracks.isEmpty) return;

    final connections = ref.read(activeConnectionsProvider);
    final first = widget.tracks.first;
    final connection = connections[first.sourceId];

    if (connection == null || connection.status != SourceStatus.connected) {
      if (context.mounted) {
        context.showWarningToast('源未连接，请先连接到 NAS');
      }
      return;
    }

    try {
      final url = await connection.adapter.fileSystem.getFileUrl(first.path);
      final musicItem = MusicItem.fromFileItem(
        first.file,
        url,
        sourceId: first.sourceId,
        title: first.title,
        artist: first.artist,
        album: first.album,
        durationMs: first.duration,
        coverData: first.coverData,
        coverUrl: first.coverFileUrl,
      );

      // 构建播放队列
      final queue = <MusicItem>[];
      for (final track in widget.tracks.take(100)) {
        final conn = connections[track.sourceId];
        if (conn == null || conn.status != SourceStatus.connected) continue;
        final trackUrl = await conn.adapter.fileSystem.getFileUrl(track.path);
        queue.add(MusicItem.fromFileItem(
          track.file,
          trackUrl,
          sourceId: track.sourceId,
          title: track.title,
          artist: track.artist,
          album: track.album,
          durationMs: track.duration,
          coverData: track.coverData,
          coverUrl: track.coverFileUrl,
        ));
      }

      ref.read(playQueueProvider.notifier).setQueue(queue);
      await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);

      if (context.mounted) {
        await MusicPlayerPage.open(context);
      }
    } on Exception catch (e) {
      if (context.mounted) {
        context.showErrorToast('播放失败: $e');
      }
    }
  }

  Future<void> _shufflePlay(BuildContext context) async {
    if (widget.tracks.isEmpty) return;

    final shuffled = List<MusicFileWithSource>.from(widget.tracks)..shuffle();
    final connections = ref.read(activeConnectionsProvider);
    final first = shuffled.first;
    final connection = connections[first.sourceId];

    if (connection == null || connection.status != SourceStatus.connected) {
      if (context.mounted) {
        context.showWarningToast('源未连接，请先连接到 NAS');
      }
      return;
    }

    try {
      final url = await connection.adapter.fileSystem.getFileUrl(first.path);
      final musicItem = MusicItem.fromFileItem(
        first.file,
        url,
        sourceId: first.sourceId,
        title: first.title,
        artist: first.artist,
        album: first.album,
        durationMs: first.duration,
        coverData: first.coverData,
        coverUrl: first.coverFileUrl,
      );

      final queue = <MusicItem>[];
      for (final track in shuffled.take(100)) {
        final conn = connections[track.sourceId];
        if (conn == null || conn.status != SourceStatus.connected) continue;
        final trackUrl = await conn.adapter.fileSystem.getFileUrl(track.path);
        queue.add(MusicItem.fromFileItem(
          track.file,
          trackUrl,
          sourceId: track.sourceId,
          title: track.title,
          artist: track.artist,
          album: track.album,
          durationMs: track.duration,
          coverData: track.coverData,
          coverUrl: track.coverFileUrl,
        ));
      }

      ref.read(playQueueProvider.notifier).setQueue(queue);
      ref.read(musicPlayerControllerProvider.notifier).setPlayMode(PlayMode.shuffle);
      await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);

      if (context.mounted) {
        await MusicPlayerPage.open(context);
      }
    } on Exception catch (e) {
      if (context.mounted) {
        context.showErrorToast('播放失败: $e');
      }
    }
  }
}

/// 艺术家视图 - 网格布局
/// 艺术家视图 - 网格布局
/// 直接从数据库获取全量艺术家数据，确保统计准确
class _ArtistsView extends ConsumerWidget {
  const _ArtistsView({
    required this.isDark,
  });

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = MusicDatabaseService();
    final config = ref.watch(mediaLibraryConfigProvider).valueOrNull;
    final enabledPaths = config
            ?.getEnabledPathsForType(MediaType.music)
            .map((p) => (sourceId: p.sourceId, path: p.path))
            .toList() ??
        [];

    return FutureBuilder<List<({String artist, int count})>>(
      future: db.getArtists(enabledPaths: enabledPaths),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _buildEmptyView('加载失败', Icons.error_outline_rounded, isDark);
        }

        final artists = snapshot.data ?? [];
        if (artists.isEmpty) {
          return _buildEmptyView('暂无艺术家', Icons.person_off_rounded, isDark);
        }

        final gridConfig = GridHelper.getMusicArtistGridConfig(context);
        return GridView.builder(
          padding: gridConfig.padding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: gridConfig.crossAxisCount,
            mainAxisSpacing: gridConfig.mainAxisSpacing,
            crossAxisSpacing: gridConfig.crossAxisSpacing,
            childAspectRatio: gridConfig.childAspectRatio,
          ),
          itemCount: artists.length,
          itemBuilder: (context, index) {
            final entry = artists[index];
            return _ArtistCardFromDb(
              artistName: entry.artist,
              count: entry.count,
              isDark: isDark,
            );
          },
        );
      },
    );
  }
}

/// 艺术家卡片 - 点击导航到详情页
class _ArtistCard extends StatelessWidget {
  const _ArtistCard({
    required this.artistName,
    required this.tracks,
    required this.isDark,
  });

  final String artistName;
  final List<MusicFileWithSource> tracks;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    // 获取第一首有封面的歌曲作为艺术家封面
    final trackWithCover = tracks.firstWhere(
      (t) => t.hasCover,
      orElse: () => tracks.first,
    );

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => CategoryDetailPage(
            title: artistName,
            subtitle: '${tracks.length} 首歌曲',
            tracks: tracks,
            icon: Icons.person_rounded,
            color: AppColors.primary,
          ),
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceVariant : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 封面区域 - 圆形头像
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: !trackWithCover.hasCover
                        ? LinearGradient(
                            colors: [
                              AppColors.primary.withValues(alpha: 0.8),
                              AppColors.secondary.withValues(alpha: 0.8),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _buildCover(trackWithCover),
                ),
              ),
            ),
            // 信息区域
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        artistName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${tracks.length} 首歌曲',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(MusicFileWithSource track) {
    if (track.coverFile != null) {
      return Image.file(
        track.coverFile!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildDefaultCover(),
      );
    }
    if (track.coverData != null) {
      return Image.memory(
        Uint8List.fromList(track.coverData!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildDefaultCover(),
      );
    }
    return _buildDefaultCover();
  }

  Widget _buildDefaultCover() => const Center(
      child: Icon(Icons.person_rounded, size: 40, color: Colors.white),
    );
}

/// 艺术家卡片（数据库版）- 点击时从数据库加载该艺术家的歌曲
class _ArtistCardFromDb extends ConsumerWidget {
  const _ArtistCardFromDb({
    required this.artistName,
    required this.count,
    required this.isDark,
  });

  final String artistName;
  final int count;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
      onTap: () => _navigateToArtist(context),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceVariant : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 封面区域 - 圆形头像
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withValues(alpha: 0.8),
                        AppColors.secondary.withValues(alpha: 0.8),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: const Center(
                    child: Icon(Icons.person_rounded, size: 40, color: Colors.white),
                  ),
                ),
              ),
            ),
            // 信息区域
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        artistName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '$count 首歌曲',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

  Future<void> _navigateToArtist(BuildContext context) async {
    final db = MusicDatabaseService();
    final tracks = await db.getByArtist(artistName, limit: 10000);
    final musicTracks = tracks
        .map((m) => MusicFileWithSource(
              file: FileItem(
                name: m.fileName,
                path: m.filePath,
                size: m.size ?? 0,
                isDirectory: false,
                modifiedTime: m.modifiedTime,
              ),
              sourceId: m.sourceId,
              title: m.title,
              artist: m.artist,
              album: m.album,
              duration: m.duration,
              year: m.year,
              genre: m.genre,
              coverPath: m.coverPath,
              metadataExtracted: true,
            ))
        .toList();

    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CategoryDetailPage(
          title: artistName,
          subtitle: '$count 首歌曲',
          tracks: musicTracks,
          icon: Icons.person_rounded,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

/// 专辑视图
/// 直接从数据库获取全量专辑数据，确保统计准确
class _AlbumsView extends ConsumerWidget {
  const _AlbumsView({
    required this.isDark,
  });

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = MusicDatabaseService();
    final config = ref.watch(mediaLibraryConfigProvider).valueOrNull;
    final enabledPaths = config
            ?.getEnabledPathsForType(MediaType.music)
            .map((p) => (sourceId: p.sourceId, path: p.path))
            .toList() ??
        [];

    return FutureBuilder<List<({String album, String? artist, int count, String? coverPath})>>(
      future: db.getAlbums(enabledPaths: enabledPaths),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _buildEmptyView('加载失败', Icons.error_outline_rounded, isDark);
        }

        final albums = snapshot.data ?? [];
        if (albums.isEmpty) {
          return _buildEmptyView('暂无专辑', Icons.album_outlined, isDark);
        }

        final gridConfig = GridHelper.getMusicAlbumGridConfig(context);
        return GridView.builder(
          padding: gridConfig.padding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: gridConfig.crossAxisCount,
            mainAxisSpacing: gridConfig.mainAxisSpacing,
            crossAxisSpacing: gridConfig.crossAxisSpacing,
            childAspectRatio: gridConfig.childAspectRatio,
          ),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final entry = albums[index];
            return _AlbumCardFromDb(
              albumName: entry.album,
              count: entry.count,
              isDark: isDark,
            );
          },
        );
      },
    );
  }
}

class _AlbumCard extends ConsumerWidget {
  const _AlbumCard({
    required this.albumName,
    required this.tracks,
    required this.isDark,
  });

  final String albumName;
  final List<MusicFileWithSource> tracks;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
      onTap: () => _showAlbumTracks(context, ref),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceVariant : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.fileAudio.withValues(alpha: 0.7),
                      AppColors.secondary.withValues(alpha: 0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: const Center(
                  child: Icon(Icons.album_rounded, size: 48, color: Colors.white),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        albumName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    Text(
                      '${tracks.length} 首歌曲',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

  void _showAlbumTracks(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.fileAudio, AppColors.secondary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.album_rounded, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              albumName,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            Text(
                              '${tracks.length} 首歌曲',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _PlayAllButton(tracks: tracks, isDark: isDark),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: tracks.length,
                itemBuilder: (context, index) => _CompactMusicTile(
                    track: tracks[index],
                    isDark: isDark,
                    allTracks: tracks,
                    trackIndex: index,
                  ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 专辑卡片（数据库版）- 点击时从数据库加载该专辑的歌曲
class _AlbumCardFromDb extends ConsumerWidget {
  const _AlbumCardFromDb({
    required this.albumName,
    required this.count,
    required this.isDark,
  });

  final String albumName;
  final int count;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
      onTap: () => _showAlbumTracks(context),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceVariant : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.fileAudio.withValues(alpha: 0.7),
                      AppColors.secondary.withValues(alpha: 0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: const Center(
                  child: Icon(Icons.album_rounded, size: 48, color: Colors.white),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        albumName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    Text(
                      '$count 首歌曲',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

  Future<void> _showAlbumTracks(BuildContext context) async {
    final db = MusicDatabaseService();
    final rawTracks = await db.getByAlbum(albumName, limit: 10000);
    final tracks = rawTracks
        .map((m) => MusicFileWithSource(
              file: FileItem(
                name: m.fileName,
                path: m.filePath,
                size: m.size ?? 0,
                isDirectory: false,
                modifiedTime: m.modifiedTime,
              ),
              sourceId: m.sourceId,
              title: m.title,
              artist: m.artist,
              album: m.album,
              duration: m.duration,
              year: m.year,
              genre: m.genre,
              coverPath: m.coverPath,
              metadataExtracted: true,
            ))
        .toList();

    if (!context.mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.fileAudio, AppColors.secondary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.album_rounded, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              albumName,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            Text(
                              '$count 首歌曲',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _PlayAllButton(tracks: tracks, isDark: isDark),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: tracks.length,
                itemBuilder: (context, index) => _CompactMusicTile(
                    track: tracks[index],
                    isDark: isDark,
                    allTracks: tracks,
                    trackIndex: index,
                  ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 文件夹视图 - 列表布局
/// 直接从数据库获取全量文件夹数据，确保统计准确
class _FoldersView extends ConsumerWidget {
  const _FoldersView({
    required this.isDark,
  });

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = MusicDatabaseService();
    // 获取媒体库配置中启用的路径
    final config = ref.watch(mediaLibraryConfigProvider).valueOrNull;
    final enabledPaths = config
            ?.getEnabledPathsForType(MediaType.music)
            .map((p) => (sourceId: p.sourceId, path: p.path))
            .toList() ??
        [];

    return FutureBuilder<List<({String folder, int count})>>(
      future: db.getFolders(enabledPaths: enabledPaths),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _buildEmptyView('加载失败', Icons.error_outline_rounded, isDark);
        }

        final folders = snapshot.data ?? [];
        if (folders.isEmpty) {
          return _buildEmptyView('暂无文件夹', Icons.folder_off_rounded, isDark);
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          itemCount: folders.length,
          itemBuilder: (context, index) {
            final entry = folders[index];
            // 从完整路径提取文件夹名（最后一个目录）
            final parts = entry.folder.split('/');
            final folderName = parts.isNotEmpty ? parts.last : entry.folder;
            return _FolderCardFromDb(
              folderName: folderName,
              folderPath: entry.folder,
              count: entry.count,
              isDark: isDark,
            );
          },
        );
      },
    );
  }
}

/// 文件夹卡片 - 点击导航到详情页
class _FolderCard extends StatelessWidget {
  const _FolderCard({
    required this.folderName,
    required this.tracks,
    required this.isDark,
  });

  final String folderName;
  final List<MusicFileWithSource> tracks;
  final bool isDark;

  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isDark ? AppColors.darkSurfaceVariant : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => CategoryDetailPage(
                title: folderName,
                subtitle: '${tracks.length} 首歌曲',
                tracks: tracks,
                icon: Icons.folder_rounded,
                color: AppColors.fileAudio,
              ),
            ),
          ),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // 文件夹图标
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.fileAudio.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.folder_rounded,
                    color: AppColors.fileAudio,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                // 文件夹信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        folderName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${tracks.length} 首歌曲',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // 箭头
                Icon(
                  Icons.chevron_right_rounded,
                  color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
}

/// 文件夹卡片（数据库版）- 点击时从数据库加载歌曲
class _FolderCardFromDb extends ConsumerWidget {
  const _FolderCardFromDb({
    required this.folderName,
    required this.folderPath,
    required this.count,
    required this.isDark,
  });

  final String folderName;
  final String folderPath;
  final int count;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isDark ? AppColors.darkSurfaceVariant : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _navigateToFolder(context),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // 文件夹图标
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.fileAudio.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.folder_rounded,
                    color: AppColors.fileAudio,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                // 文件夹信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        folderName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$count 首歌曲',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // 箭头
                Icon(
                  Icons.chevron_right_rounded,
                  color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );

  Future<void> _navigateToFolder(BuildContext context) async {
    final db = MusicDatabaseService();
    // 加载该文件夹下的所有歌曲（不分页）
    final tracks = await db.getByFolder(folderPath, limit: 10000);
    final musicTracks = tracks
        .map((m) => MusicFileWithSource(
              file: FileItem(
                name: m.fileName,
                path: m.filePath,
                size: m.size ?? 0,
                isDirectory: false,
                modifiedTime: m.modifiedTime,
              ),
              sourceId: m.sourceId,
              title: m.title,
              artist: m.artist,
              album: m.album,
              duration: m.duration,
              year: m.year,
              genre: m.genre,
              coverPath: m.coverPath,
              metadataExtracted: true,
            ))
        .toList();

    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CategoryDetailPage(
          title: folderName,
          subtitle: '$count 首歌曲',
          tracks: musicTracks,
          icon: Icons.folder_rounded,
          color: AppColors.fileAudio,
        ),
      ),
    );
  }
}

/// 流派视图 - 网格布局
/// 直接从数据库获取全量流派数据，确保统计准确
class _GenresView extends ConsumerWidget {
  const _GenresView({
    required this.isDark,
  });

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = MusicDatabaseService();
    final config = ref.watch(mediaLibraryConfigProvider).valueOrNull;
    final enabledPaths = config
            ?.getEnabledPathsForType(MediaType.music)
            .map((p) => (sourceId: p.sourceId, path: p.path))
            .toList() ??
        [];

    return FutureBuilder<List<({String genre, int count})>>(
      future: db.getGenres(enabledPaths: enabledPaths),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _buildEmptyView('加载失败', Icons.error_outline_rounded, isDark);
        }

        final genres = snapshot.data ?? [];
        if (genres.isEmpty) {
          return _buildEmptyView('暂无流派信息', Icons.category_outlined, isDark);
        }

        final gridConfig = GridHelper.getMusicCategoryGridConfig(context);
        return GridView.builder(
          padding: gridConfig.padding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: gridConfig.crossAxisCount,
            mainAxisSpacing: gridConfig.mainAxisSpacing,
            crossAxisSpacing: gridConfig.crossAxisSpacing,
            childAspectRatio: gridConfig.childAspectRatio,
          ),
          itemCount: genres.length,
          itemBuilder: (context, index) {
            final entry = genres[index];
            return _GenreCardFromDb(
              genreName: entry.genre,
              count: entry.count,
              isDark: isDark,
              color: _getColorForIndex(index),
            );
          },
        );
      },
    );
  }

  Color _getColorForIndex(int index) {
    final colors = [
      Colors.pink,
      Colors.purple,
      Colors.indigo,
      Colors.blue,
      Colors.cyan,
      Colors.teal,
      Colors.green,
      Colors.orange,
      Colors.deepOrange,
      Colors.red,
    ];
    return colors[index % colors.length];
  }
}

/// 流派卡片 - 点击导航到详情页
class _GenreCard extends StatelessWidget {
  const _GenreCard({
    required this.genreName,
    required this.tracks,
    required this.isDark,
    required this.color,
  });

  final String genreName;
  final List<MusicFileWithSource> tracks;
  final bool isDark;
  final Color color;

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => CategoryDetailPage(
            title: genreName,
            subtitle: '${tracks.length} 首歌曲',
            tracks: tracks,
            icon: Icons.category_rounded,
            color: color,
          ),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withValues(alpha: 0.9), color.withValues(alpha: 0.6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // 装饰性图标
            Positioned(
              right: -10,
              bottom: -10,
              child: Icon(
                Icons.category_rounded,
                size: 60,
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
            // 内容
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    genreName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${tracks.length} 首歌曲',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.8),
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

/// 流派卡片（数据库版）- 点击时从数据库加载歌曲
class _GenreCardFromDb extends ConsumerWidget {
  const _GenreCardFromDb({
    required this.genreName,
    required this.count,
    required this.isDark,
    required this.color,
  });

  final String genreName;
  final int count;
  final bool isDark;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
      onTap: () => _navigateToGenre(context),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withValues(alpha: 0.9), color.withValues(alpha: 0.6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // 装饰性图标
            Positioned(
              right: -10,
              bottom: -10,
              child: Icon(
                Icons.category_rounded,
                size: 60,
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
            // 内容
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    genreName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$count 首歌曲',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

  Future<void> _navigateToGenre(BuildContext context) async {
    final db = MusicDatabaseService();
    final tracks = await db.getByGenre(genreName, limit: 10000);
    final musicTracks = tracks
        .map((m) => MusicFileWithSource(
              file: FileItem(
                name: m.fileName,
                path: m.filePath,
                size: m.size ?? 0,
                isDirectory: false,
                modifiedTime: m.modifiedTime,
              ),
              sourceId: m.sourceId,
              title: m.title,
              artist: m.artist,
              album: m.album,
              duration: m.duration,
              year: m.year,
              genre: m.genre,
              coverPath: m.coverPath,
              metadataExtracted: true,
            ))
        .toList();

    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CategoryDetailPage(
          title: genreName,
          subtitle: '$count 首歌曲',
          tracks: musicTracks,
          icon: Icons.category_rounded,
          color: color,
        ),
      ),
    );
  }
}

/// 年代视图 - 网格布局
/// 直接从数据库获取全量年代数据，确保统计准确
class _YearsView extends ConsumerWidget {
  const _YearsView({
    required this.isDark,
  });

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = MusicDatabaseService();
    final config = ref.watch(mediaLibraryConfigProvider).valueOrNull;
    final enabledPaths = config
            ?.getEnabledPathsForType(MediaType.music)
            .map((p) => (sourceId: p.sourceId, path: p.path))
            .toList() ??
        [];

    return FutureBuilder<List<({int year, int count})>>(
      future: db.getYears(enabledPaths: enabledPaths),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _buildEmptyView('加载失败', Icons.error_outline_rounded, isDark);
        }

        final yearData = snapshot.data ?? [];
        if (yearData.isEmpty) {
          return _buildEmptyView('暂无年代信息', Icons.date_range_rounded, isDark);
        }

        // 按年代（每10年）重新分组
        final decadeMap = <String, int>{};
        for (final item in yearData) {
          final decade = (item.year ~/ 10) * 10;
          final decadeLabel = '${decade}s';
          decadeMap[decadeLabel] = (decadeMap[decadeLabel] ?? 0) + item.count;
        }
        
        final decades = decadeMap.entries.toList()
          ..sort((a, b) => b.key.compareTo(a.key));

        final gridConfig = GridHelper.getMusicCategoryGridConfig(context);
        return GridView.builder(
          padding: gridConfig.padding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: gridConfig.crossAxisCount,
            mainAxisSpacing: gridConfig.mainAxisSpacing,
            crossAxisSpacing: gridConfig.crossAxisSpacing,
            childAspectRatio: gridConfig.childAspectRatio,
          ),
          itemCount: decades.length,
          itemBuilder: (context, index) {
            final entry = decades[index];
            return _YearCardFromDb(
              decadeLabel: entry.key,
              count: entry.value,
              isDark: isDark,
              color: _getColorForDecade(entry.key),
            );
          },
        );
      },
    );
  }

  Color _getColorForDecade(String decade) {
    switch (decade) {
      case '2020s':
        return Colors.purple;
      case '2010s':
        return Colors.blue;
      case '2000s':
        return Colors.teal;
      case '1990s':
        return Colors.green;
      case '1980s':
        return Colors.orange;
      case '1970s':
        return Colors.deepOrange;
      case '1960s':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

/// 年代卡片 - 点击导航到详情页
class _YearCard extends StatelessWidget {
  const _YearCard({
    required this.yearLabel,
    required this.tracks,
    required this.isDark,
    required this.color,
  });

  final String yearLabel;
  final List<MusicFileWithSource> tracks;
  final bool isDark;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final displayTitle = yearLabel == '未知年代' ? yearLabel : '$yearLabel 年代';
    final displayYear = yearLabel == '未知年代' ? '?' : yearLabel.replaceAll('s', '');

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => CategoryDetailPage(
            title: displayTitle,
            subtitle: '${tracks.length} 首歌曲',
            tracks: tracks,
            icon: Icons.date_range_rounded,
            color: color,
          ),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withValues(alpha: 0.9), color.withValues(alpha: 0.6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // 背景年份
            Positioned(
              right: 8,
              bottom: -10,
              child: Text(
                displayYear,
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withValues(alpha: 0.15),
                ),
              ),
            ),
            // 内容
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      displayYear,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${tracks.length} 首歌曲',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.8),
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
}

/// 年代卡片（数据库版）- 点击时从数据库加载该年代的歌曲
class _YearCardFromDb extends ConsumerWidget {
  const _YearCardFromDb({
    required this.decadeLabel,
    required this.count,
    required this.isDark,
    required this.color,
  });

  final String decadeLabel;
  final int count;
  final bool isDark;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayYear = decadeLabel.replaceAll('s', '');

    return GestureDetector(
      onTap: () => _navigateToDecade(context),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withValues(alpha: 0.9), color.withValues(alpha: 0.6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // 背景年份
            Positioned(
              right: 8,
              bottom: -10,
              child: Text(
                displayYear,
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withValues(alpha: 0.15),
                ),
              ),
            ),
            // 内容
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      displayYear,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$count 首歌曲',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.8),
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

  Future<void> _navigateToDecade(BuildContext context) async {
    final db = MusicDatabaseService();
    // 获取该年代范围内的所有年份
    final decadeStart = int.tryParse(decadeLabel.replaceAll('s', '')) ?? 2000;
    final decadeEnd = decadeStart + 9;
    
    // 从数据库获取该年代所有歌曲
    final allTracks = <MusicTrackEntity>[];
    for (var year = decadeStart; year <= decadeEnd; year++) {
      final tracks = await db.getByYear(year, limit: 10000);
      allTracks.addAll(tracks);
    }
    
    final musicTracks = allTracks
        .map((m) => MusicFileWithSource(
              file: FileItem(
                name: m.fileName,
                path: m.filePath,
                size: m.size ?? 0,
                isDirectory: false,
                modifiedTime: m.modifiedTime,
              ),
              sourceId: m.sourceId,
              title: m.title,
              artist: m.artist,
              album: m.album,
              duration: m.duration,
              year: m.year,
              genre: m.genre,
              coverPath: m.coverPath,
              metadataExtracted: true,
            ))
        .toList();

    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CategoryDetailPage(
          title: '$decadeLabel 年代',
          subtitle: '$count 首歌曲',
          tracks: musicTracks,
          icon: Icons.date_range_rounded,
          color: color,
        ),
      ),
    );
  }
}

/// 收藏视图
class _FavoritesView extends ConsumerWidget {
  const _FavoritesView({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritesState = ref.watch(musicFavoritesProvider);
    final favorites = favoritesState.favorites;

    if (favorites.isEmpty) {
      return _buildEmptyView('暂无收藏', Icons.favorite_outline_rounded, isDark);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: favorites.length,
      itemBuilder: (context, index) {
        final item = favorites[index].toMusicItem();
        return _FavoriteTrackTile(item: item, isDark: isDark);
      },
    );
  }
}

class _FavoriteTrackTile extends ConsumerWidget {
  const _FavoriteTrackTile({
    required this.item,
    required this.isDark,
  });

  final MusicItem item;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(currentMusicProvider);
    final isPlaying = currentMusic?.id == item.id;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isPlaying
            ? AppColors.fileAudio.withValues(alpha: isDark ? 0.15 : 0.1)
            : (isDark
                ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
                : Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPlaying
              ? AppColors.fileAudio.withValues(alpha: 0.3)
              : (isDark
                  ? AppColors.darkOutline.withValues(alpha: 0.2)
                  : Colors.grey.withValues(alpha: 0.2)),
        ),
      ),
      child: ListTile(
        onTap: () async {
          await ref.read(musicPlayerControllerProvider.notifier).play(item);
          if (context.mounted) {
            await MusicPlayerPage.open(context);
          }
        },
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: item.coverData == null && item.coverUrl == null
                ? LinearGradient(
                    colors: isPlaying
                        ? [AppColors.fileAudio, AppColors.secondary]
                        : [
                            AppColors.primary.withValues(alpha: 0.7),
                            AppColors.secondary.withValues(alpha: 0.7),
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: _buildCover(isPlaying),
        ),
        title: Text(
          item.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
            color: isPlaying ? AppColors.fileAudio : (isDark ? Colors.white : Colors.black87),
          ),
        ),
        subtitle: Text(
          item.displayArtist,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
          ),
        ),
        trailing: IconButton(
          icon: Icon(Icons.favorite_rounded, color: AppColors.error),
          onPressed: () async {
            await ref.read(musicFavoritesProvider.notifier).toggleFavorite(item);
          },
        ),
      ),
    );
  }

  Widget _buildCover(bool isPlaying) {
    // 优先使用内嵌封面数据
    if (item.coverData != null && item.coverData!.isNotEmpty) {
      return Image.memory(
        Uint8List.fromList(item.coverData!),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _buildPlaceholder(isPlaying),
      );
    }

    // 其次使用封面 URL
    if (item.coverUrl != null && item.coverUrl!.isNotEmpty) {
      final coverUrl = item.coverUrl!;
      Widget coverImage;

      // 支持 file:// URL 和网络 URL
      if (coverUrl.startsWith('file://')) {
        final filePath = coverUrl.substring(7); // 移除 'file://' 前缀
        coverImage = Image.file(
          File(filePath),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _buildPlaceholder(isPlaying),
        );
      } else {
        coverImage = Image.network(
          coverUrl,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _buildPlaceholder(isPlaying),
        );
      }
      return coverImage;
    }

    return _buildPlaceholder(isPlaying);
  }

  Widget _buildPlaceholder(bool isPlaying) => Icon(
        isPlaying ? Icons.equalizer_rounded : Icons.music_note_rounded,
        color: Colors.white.withValues(alpha: 0.8),
        size: 24,
      );
}

/// 最近播放视图
class _RecentView extends ConsumerWidget {
  const _RecentView({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentTracks = ref.watch(recentTracksProvider);

    if (recentTracks.isEmpty) {
      return _buildEmptyView('暂无播放记录', Icons.history_rounded, isDark);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: recentTracks.length,
      itemBuilder: (context, index) {
        final item = recentTracks[index];
        return _RecentTrackTile(item: item, isDark: isDark);
      },
    );
  }
}

class _RecentTrackTile extends ConsumerWidget {
  const _RecentTrackTile({
    required this.item,
    required this.isDark,
  });

  final MusicItem item;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(currentMusicProvider);
    final isPlaying = currentMusic?.id == item.id;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isPlaying
            ? AppColors.fileAudio.withValues(alpha: isDark ? 0.15 : 0.1)
            : (isDark
                ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
                : Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPlaying
              ? AppColors.fileAudio.withValues(alpha: 0.3)
              : (isDark
                  ? AppColors.darkOutline.withValues(alpha: 0.2)
                  : Colors.grey.withValues(alpha: 0.2)),
        ),
      ),
      child: ListTile(
        onTap: () async {
          await ref.read(musicPlayerControllerProvider.notifier).play(item);
          if (context.mounted) {
            await MusicPlayerPage.open(context);
          }
        },
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: item.coverData == null && item.coverUrl == null
                ? LinearGradient(
                    colors: isPlaying
                        ? [AppColors.fileAudio, AppColors.secondary]
                        : [
                            AppColors.primary.withValues(alpha: 0.7),
                            AppColors.secondary.withValues(alpha: 0.7),
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: _buildCover(isPlaying),
        ),
        title: Text(
          item.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
            color: isPlaying ? AppColors.fileAudio : (isDark ? Colors.white : Colors.black87),
          ),
        ),
        subtitle: Text(
          item.displayArtist,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
          ),
        ),
        trailing: Icon(
          Icons.play_arrow_rounded,
          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildCover(bool isPlaying) {
    // 优先使用嵌入的封面数据
    if (item.coverData != null && item.coverData!.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            Uint8List.fromList(item.coverData!),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _buildPlaceholder(isPlaying),
          ),
          if (isPlaying) _buildPlayingOverlay(),
        ],
      );
    }

    // 其次使用封面 URL
    if (item.coverUrl != null && item.coverUrl!.isNotEmpty) {
      final coverUrl = item.coverUrl!;
      Widget coverImage;

      // 支持 file:// URL 和网络 URL
      if (coverUrl.startsWith('file://')) {
        final filePath = coverUrl.substring(7); // 移除 'file://' 前缀
        coverImage = Image.file(
          File(filePath),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _buildPlaceholder(isPlaying),
        );
      } else {
        coverImage = Image.network(
          coverUrl,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _buildPlaceholder(isPlaying),
        );
      }

      return Stack(
        fit: StackFit.expand,
        children: [
          coverImage,
          if (isPlaying) _buildPlayingOverlay(),
        ],
      );
    }

    // 默认显示音符图标
    return _buildPlaceholder(isPlaying);
  }

  Widget _buildPlaceholder(bool isPlaying) => Center(
        child: Icon(
          isPlaying ? Icons.equalizer_rounded : Icons.music_note_rounded,
          color: Colors.white,
          size: 24,
        ),
      );

  Widget _buildPlayingOverlay() => ColoredBox(
        color: Colors.black.withValues(alpha: 0.3),
        child: const Center(
          child: Icon(
            Icons.equalizer_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
      );
}

/// 歌单列表视图
class _PlaylistsView extends ConsumerWidget {
  const _PlaylistsView({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistState = ref.watch(playlistProvider);
    final playlists = playlistState.playlists;

    if (playlistState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // 创建歌单按钮
        Padding(
          padding: const EdgeInsets.all(16),
          child: _CreatePlaylistButton(isDark: isDark),
        ),
        // 歌单列表
        Expanded(
          child: playlists.isEmpty
              ? _buildEmptyView('暂无歌单', Icons.playlist_play_rounded, isDark)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    return _PlaylistTile(playlist: playlist, isDark: isDark);
                  },
                ),
        ),
      ],
    );
  }
}

/// 创建歌单按钮
class _CreatePlaylistButton extends ConsumerWidget {
  const _CreatePlaylistButton({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showCreatePlaylistDialog(context, ref),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  '创建新歌单',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  void _showCreatePlaylistDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建歌单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '歌单名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                await ref.read(playlistProvider.notifier).createPlaylist(name: name);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }
}

/// 歌单列表项
class _PlaylistTile extends ConsumerWidget {
  const _PlaylistTile({
    required this.playlist,
    required this.isDark,
  });

  final PlaylistEntry playlist;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.2)
                : Colors.grey.withValues(alpha: 0.2),
          ),
        ),
        child: ListTile(
          onTap: () => _openPlaylistDetail(context, ref),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF9C27B0).withValues(alpha: 0.8),
                  const Color(0xFFE91E63).withValues(alpha: 0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.playlist_play_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          title: Text(
            playlist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          subtitle: Text(
            '${playlist.trackCount} 首歌曲',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
          ),
          trailing: PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert_rounded,
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
            onSelected: (value) => _handleMenuAction(context, ref, value),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(Icons.edit_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('重命名'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_rounded, size: 20, color: AppColors.error),
                    SizedBox(width: 12),
                    Text('删除', style: TextStyle(color: AppColors.error)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  void _openPlaylistDetail(BuildContext context, WidgetRef ref) {
    PlaylistDetailPage.open(context, playlist);
  }

  void _handleMenuAction(BuildContext context, WidgetRef ref, String action) {
    switch (action) {
      case 'rename':
        _showRenameDialog(context, ref);
      case 'delete':
        _showDeleteConfirm(context, ref);
    }
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: playlist.name);

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名歌单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '歌单名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty && name != playlist.name) {
                await ref.read(playlistProvider.notifier).renamePlaylist(playlist.id, name);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除歌单'),
        content: Text('确定要删除歌单「${playlist.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            onPressed: () async {
              await ref.read(playlistProvider.notifier).deletePlaylist(playlist.id);
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// 排序方向切换按钮
class _SortDirectionButton extends StatelessWidget {
  const _SortDirectionButton({
    required this.direction,
    required this.isDark,
    required this.onTap,
  });

  final SortDirection direction;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                direction == SortDirection.ascending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: 4),
              Text(
                direction == SortDirection.ascending ? '升序' : '降序',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
}

/// 排序选项列表项
class _SortOptionTile extends StatelessWidget {
  const _SortOptionTile({
    required this.option,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  final MusicSortOption option;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.15)
              : (isDark ? Colors.grey[800] : Colors.grey[100]),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          option.icon,
          color: isSelected
              ? AppColors.primary
              : (isDark ? Colors.white70 : Colors.black54),
          size: 20,
        ),
      ),
      title: Text(
        option.label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          color: isSelected
              ? AppColors.primary
              : (isDark ? Colors.white : Colors.black87),
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check_rounded, color: AppColors.primary, size: 22)
          : null,
      onTap: onTap,
    );
}

/// Spotify 风格播放按钮
class _SpotifyPlayButton extends StatelessWidget {
  const _SpotifyPlayButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.isPrimary = true,
    this.isDark = false,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final bool isPrimary;
  final bool isDark;

  @override
  Widget build(BuildContext context) => Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          decoration: BoxDecoration(
            gradient: isPrimary
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.secondary],
                  )
                : null,
            color: isPrimary
                ? null
                : (isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.grey[200]),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: isPrimary
                      ? Colors.white
                      : (isDark ? Colors.white : Colors.black87),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: isPrimary
                        ? Colors.white
                        : (isDark ? Colors.white : Colors.black87),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
}

/// Spotify 风格图标按钮（带文字）
class _SpotifyIconButton extends StatelessWidget {
  const _SpotifyIconButton({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.arrow_drop_down_rounded,
                size: 18,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ],
          ),
        ),
      ),
    );
}

/// 表格头部
class _TableHeader extends StatelessWidget {
  const _TableHeader({
    required this.title,
    this.align = TextAlign.left,
  });

  final String title;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      title,
      textAlign: align,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white54 : Colors.black54,
      ),
    );
  }
}

/// 音乐表格行
class _MusicTableRow extends ConsumerWidget {
  const _MusicTableRow({
    required this.track,
    required this.index,
    required this.isDark,
    required this.isEven,
    required this.allTracks,
    required this.colorScheme,
  });

  final MusicFileWithSource track;
  final int index;
  final bool isDark;
  final bool isEven;
  final List<MusicFileWithSource> allTracks;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(currentMusicProvider);
    final isPlaying = currentMusic?.path == track.path;
    final durationSeconds = track.duration;
    final durationText = durationSeconds != null && durationSeconds > 0
        ? '${durationSeconds ~/ 60}:${(durationSeconds % 60).toString().padLeft(2, '0')}'
        : '--:--';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _playTrack(context, ref),
        onSecondaryTap: () => _showContextMenu(context, ref),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isPlaying
                ? colorScheme.primary.withValues(alpha: 0.1)
                : isEven
                    ? (isDark ? Colors.white.withValues(alpha: 0.02) : Colors.black.withValues(alpha: 0.02))
                    : Colors.transparent,
          ),
          child: Row(
            children: [
              // 序号/播放状态
              SizedBox(
                width: 40,
                child: isPlaying
                    ? Icon(Icons.volume_up_rounded, size: 16, color: colorScheme.primary)
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
              ),
              // 标题
              Expanded(
                flex: 4,
                child: Text(
                  track.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isPlaying ? FontWeight.w600 : FontWeight.normal,
                    color: isPlaying
                        ? colorScheme.primary
                        : (isDark ? Colors.white : Colors.black87),
                  ),
                ),
              ),
              // 艺术家
              Expanded(
                flex: 2,
                child: Text(
                  track.displayArtist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ),
              // 专辑
              Expanded(
                flex: 2,
                child: Text(
                  track.displayAlbum,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ),
              // 时长
              SizedBox(
                width: 60,
                child: Text(
                  durationText,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ),
              // 更多按钮
              SizedBox(
                width: 48,
                child: IconButton(
                  onPressed: () => _showContextMenu(context, ref),
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    size: 18,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _playTrack(BuildContext context, WidgetRef ref) async {
    final musicItem = track.toMusicItem();
    final queue = allTracks.map((t) => t.toMusicItem()).toList();

    ref.read(playQueueProvider.notifier).setQueue(queue);
    ref.read(musicPlayerControllerProvider.notifier).updateCurrentIndex(index);
    await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);

    if (context.mounted) {
      await MusicPlayerPage.open(context);
    }
  }

  void _showContextMenu(BuildContext context, WidgetRef ref) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx + size.width - 48,
        position.dy,
        position.dx + size.width,
        position.dy + size.height,
      ),
      items: [
        const PopupMenuItem(value: 'play', child: Text('播放')),
        const PopupMenuItem(value: 'queue', child: Text('添加到队列')),
        const PopupMenuItem(value: 'playlist', child: Text('添加到播放列表')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'artist', child: Text('查看艺术家')),
        const PopupMenuItem(value: 'album', child: Text('查看专辑')),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'play':
          AppError.fireAndForget(_playTrack(context, ref), action: 'musicList.playTrack');
        case 'queue':
          ref.read(playQueueProvider.notifier).addToQueue(track.toMusicItem());
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已添加到播放队列'), duration: Duration(seconds: 1)),
            );
          }
        // 其他操作...
      }
    });
  }
}

/// 现代风格音乐列表项
class _ModernMusicTile extends ConsumerWidget {
  const _ModernMusicTile({
    required this.track,
    required this.index,
    required this.isDark,
    required this.allTracks,
  });

  final MusicFileWithSource track;
  final int index;
  final bool isDark;
  final List<MusicFileWithSource> allTracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(currentMusicProvider);
    final isPlaying = currentMusic?.path == track.path;
    final title = track.displayTitle;
    final artist = track.displayArtist;
    // 动态获取有效的封面路径（解决 iOS 沙盒 UUID 变化问题）
    final effectiveCoverPath = _getEffectiveCoverPath(track);
    final coverData = track.coverData;

    // 检查源是否已连接
    final connections = ref.watch(activeConnectionsProvider);
    final connection = connections[track.sourceId];
    final isConnected = connection != null && connection.status == SourceStatus.connected;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isPlaying
            ? AppColors.primary.withValues(alpha: isDark ? 0.15 : 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _playTrack(context, ref),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // 序号或播放指示器
                SizedBox(
                  width: 32,
                  child: isPlaying
                      ? _PlayingIndicator(isDark: isDark)
                      : Text(
                          '${index + 1}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? Colors.grey[500]
                                : Colors.grey[600],
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                // 封面
                _buildCover(effectiveCoverPath, coverData, title, isPlaying, isConnected),
                const SizedBox(width: 14),
                // 标题和艺术家
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
                          color: isPlaying
                              ? AppColors.primary
                              : isConnected
                                  ? (isDark ? Colors.white : Colors.black87)
                                  : (isDark ? Colors.grey[600] : Colors.grey[500]),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (!isConnected) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '离线',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.warning,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.grey[500] : Colors.grey[600],
                              ),
                            ),
                          ),
                          if (track.duration != null) ...[
                            Text(
                              ' · ',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.grey[600] : Colors.grey[500],
                              ),
                            ),
                            Text(
                              track.durationText,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.grey[600] : Colors.grey[500],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // 更多按钮
                IconButton(
                  onPressed: () => _showMoreOptions(context, ref),
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                    size: 22,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover(String? coverPath, List<int>? coverData, String title, bool isPlaying, bool isConnected) {
    final size = 52.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
        boxShadow: isPlaying
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: coverPath != null && coverPath.isNotEmpty
          ? Image.file(
              File(coverPath),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _buildFallbackCover(title, isConnected),
            )
          : coverData != null
              ? Image.memory(
                  Uint8List.fromList(coverData),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => _buildFallbackCover(title, isConnected),
            )
          : _buildFallbackCover(title, isConnected),
    );
  }

  Widget _buildFallbackCover(String title, bool isConnected) {
    final gradientColors = _getGradientForTitle(title);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          title.isNotEmpty ? title[0].toUpperCase() : '♪',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Color> _getGradientForTitle(String title) {
    final hash = title.hashCode;
    final gradients = [
      [const Color(0xFF667eea), const Color(0xFF764ba2)],
      [const Color(0xFFf093fb), const Color(0xFFf5576c)],
      [const Color(0xFF4facfe), const Color(0xFF00f2fe)],
      [const Color(0xFF43e97b), const Color(0xFF38f9d7)],
      [const Color(0xFFfa709a), const Color(0xFFfee140)],
      [const Color(0xFF30cfd0), const Color(0xFF330867)],
      [const Color(0xFFa8edea), const Color(0xFFfed6e3)],
      [const Color(0xFFff9a9e), const Color(0xFFfecfef)],
    ];
    return gradients[hash.abs() % gradients.length];
  }

  Future<void> _playTrack(BuildContext context, WidgetRef ref) async {
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[track.sourceId];
    if (connection == null || connection.status != SourceStatus.connected) {
      if (context.mounted) {
        context.showWarningToast('源未连接，请先连接到 NAS');
      }
      return;
    }

    try {
      final url = await connection.adapter.fileSystem.getFileUrl(track.path);
      final musicItem = MusicItem.fromFileItem(
        track.file,
        url,
        sourceId: track.sourceId,
        title: track.title,
        artist: track.artist,
        album: track.album,
        durationMs: track.duration,
        trackNumber: track.trackNumber,
        year: track.year,
        genre: track.genre,
        coverData: track.coverData,
        coverUrl: track.coverFileUrl,
      );

      // 设置播放队列
      final queue = <MusicItem>[];
      for (final t in allTracks) {
        final conn = connections[t.sourceId];
        if (conn == null || conn.status != SourceStatus.connected) continue;
        final trackUrl = await conn.adapter.fileSystem.getFileUrl(t.path);
        queue.add(MusicItem.fromFileItem(
          t.file,
          trackUrl,
          sourceId: t.sourceId,
          title: t.title,
          artist: t.artist,
          album: t.album,
          durationMs: t.duration,
          coverData: t.coverData,
          coverUrl: t.coverFileUrl,
        ));
      }

      ref.read(playQueueProvider.notifier).setQueue(queue);
      ref.read(musicPlayerControllerProvider.notifier).updateCurrentIndex(index);
      await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);

      if (context.mounted) {
        await MusicPlayerPage.open(context);
      }
    } on Exception catch (e) {
      if (context.mounted) {
        context.showErrorToast('播放失败: $e');
      }
    }
  }

  void _showMoreOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖拽指示器
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 歌曲信息头
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: track.coverFile != null
                        ? Image.file(
                            track.coverFile!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.music_note_rounded,
                              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                            ),
                          )
                        : track.coverData != null
                            ? Image.memory(
                                Uint8List.fromList(track.coverData!),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Icon(
                                  Icons.music_note_rounded,
                                  color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                                ),
                              )
                            : Icon(
                                Icons.music_note_rounded,
                                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                              ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        Text(
                          track.displayArtist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _BottomSheetOption(
              icon: Icons.queue_play_next_rounded,
              label: '下一首播放',
              isDark: isDark,
              onTap: () {
                Navigator.pop(context);
                _addToPlayNext(context, ref);
              },
            ),
            _BottomSheetOption(
              icon: Icons.playlist_add_rounded,
              label: '添加到播放队列',
              isDark: isDark,
              onTap: () {
                Navigator.pop(context);
                _addToQueue(context, ref);
              },
            ),
            _BottomSheetOption(
              icon: Icons.favorite_border_rounded,
              label: '添加到我喜欢',
              isDark: isDark,
              onTap: () {
                Navigator.pop(context);
                _addToFavorites(context, ref);
              },
            ),
            _BottomSheetOption(
              icon: Icons.playlist_add_check_rounded,
              label: '添加到歌单',
              isDark: isDark,
              onTap: () {
                Navigator.pop(context);
                _showPlaylistSelector(context, ref);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 添加到下一首播放
  void _addToPlayNext(BuildContext context, WidgetRef ref) {
    final musicItem = track.toMusicItem();
    final currentIndex = ref.read(musicPlayerControllerProvider).currentIndex;
    ref.read(playQueueProvider.notifier).addNext(musicItem, currentIndex);
    if (context.mounted) {
      context.showSuccessToast('已添加「${track.displayTitle}」到下一首播放');
    }
  }

  /// 添加到播放队列
  void _addToQueue(BuildContext context, WidgetRef ref) {
    final musicItem = track.toMusicItem();
    ref.read(playQueueProvider.notifier).addToQueue(musicItem);
    if (context.mounted) {
      context.showSuccessToast('已添加「${track.displayTitle}」到播放队列');
    }
  }

  /// 添加到收藏
  Future<void> _addToFavorites(BuildContext context, WidgetRef ref) async {
    final musicItem = track.toMusicItem();
    final isFavorite = await ref.read(musicFavoritesProvider.notifier).toggleFavorite(musicItem);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isFavorite ? '已添加到我喜欢' : '已从我喜欢中移除'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// 显示歌单选择器
  void _showPlaylistSelector(BuildContext context, WidgetRef ref) {
    final playlistState = ref.read(playlistProvider);
    final playlists = playlistState.playlists;
    // 保存根 Navigator context，用于后续对话框
    final rootContext = Navigator.of(context, rootNavigator: true).context;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (dialogContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 拖拽指示器
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // 标题
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.playlist_add_rounded,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '添加到歌单',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  // 新建歌单按钮
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      // 使用 rootContext 避免 context 失效问题
                      _showCreatePlaylistDialog(rootContext, ref);
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('新建'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 歌单列表
            if (playlists.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.queue_music_rounded,
                        size: 48,
                        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '暂无歌单',
                        style: TextStyle(
                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '点击右上角新建歌单',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[500] : Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(dialogContext).size.height * 0.4,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlists.length,
                  itemBuilder: (_, index) {
                    final playlist = playlists[index];
                    return ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.queue_music_rounded,
                          color: AppColors.primary,
                        ),
                      ),
                      title: Text(
                        playlist.name,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      subtitle: Text(
                        '${playlist.trackCount} 首歌曲',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[500] : Colors.grey[600],
                        ),
                      ),
                      onTap: () async {
                        Navigator.pop(dialogContext);
                        await ref.read(playlistProvider.notifier).addToPlaylist(
                          playlist.id,
                          track.path,
                        );
                        if (rootContext.mounted) {
                          ScaffoldMessenger.of(rootContext).showSnackBar(
                            SnackBar(
                              content: Text('已添加到「${playlist.name}」'),
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 显示创建歌单对话框
  void _showCreatePlaylistDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建歌单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '歌单名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(dialogContext);
                final playlist = await ref.read(playlistProvider.notifier).createPlaylist(
                  name: name,
                  initialTracks: [track.path],
                );
                if (context.mounted && playlist != null) {
                  context.showSuccessToast('已创建歌单「$name」并添加歌曲');
                }
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }
}

/// 播放中动画指示器
class _PlayingIndicator extends StatefulWidget {
  const _PlayingIndicator({required this.isDark});
  final bool isDark;

  @override
  State<_PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<_PlayingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final animValue = (_controller.value + delay) % 1.0;
            return Container(
              width: 3,
              height: 8 + (animValue * 8),
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
    );
}

/// 底部弹窗选项
class _BottomSheetOption extends StatelessWidget {
  const _BottomSheetOption({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
      leading: Icon(icon, color: isDark ? Colors.white70 : Colors.black87),
      title: Text(
        label,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      ),
      onTap: onTap,
    );
}

/// 紧凑型音乐列表项
class _CompactMusicTile extends ConsumerWidget {
  const _CompactMusicTile({
    required this.track,
    required this.isDark,
    this.allTracks,
    this.trackIndex,
  });

  final MusicFileWithSource track;
  final bool isDark;
  final List<MusicFileWithSource>? allTracks;
  final int? trackIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 使用元数据（如已提取）或从文件名解析
    final title = track.displayTitle;
    final artist = track.displayArtist;
    // 动态获取有效的封面路径（解决 iOS 沙盒 UUID 变化问题）
    final effectiveCoverPath = _getEffectiveCoverPath(track);
    final coverData = track.coverData;

    // 检查源是否已连接
    final connections = ref.watch(activeConnectionsProvider);
    final connection = connections[track.sourceId];
    final isConnected = connection != null && connection.status == SourceStatus.connected;

    Widget buildFallbackIcon() => Icon(
          Icons.music_note_rounded,
          size: 20,
          color: isConnected
              ? (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant)
              : (isDark ? Colors.grey[700] : Colors.grey[350]),
        );

    return ListTile(
      onTap: () => _playTrack(context, ref),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Stack(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: effectiveCoverPath != null && effectiveCoverPath.isNotEmpty
                ? Image.file(
                    File(effectiveCoverPath),
                    fit: BoxFit.cover,
                    width: 40,
                    height: 40,
                    errorBuilder: (context, error, stackTrace) => buildFallbackIcon(),
                  )
                : coverData != null
                    ? Image.memory(
                        Uint8List.fromList(coverData),
                        fit: BoxFit.cover,
                        width: 40,
                        height: 40,
                        errorBuilder: (context, error, stackTrace) => buildFallbackIcon(),
                      )
                    : buildFallbackIcon(),
          ),
          if (!isConnected)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: AppColors.warning,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.link_off,
                  size: 8,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          color: isConnected
              ? (isDark ? Colors.white : Colors.black87)
              : (isDark ? Colors.grey[500] : Colors.grey[600]),
        ),
      ),
      subtitle: Text(
        isConnected
            ? '$artist${track.duration != null ? ' · ${track.durationText}' : ''}'
            : '$artist • 源未连接',
        style: TextStyle(
          fontSize: 11,
          color: isConnected
              ? (isDark ? Colors.grey[500] : Colors.grey[600])
              : AppColors.warning,
        ),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) => _handleAction(context, ref, value),
        icon: Icon(
          Icons.more_vert_rounded,
          size: 20,
          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
        ),
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'play_next', child: Text('下一首播放')),
          const PopupMenuItem(value: 'add_to_queue', child: Text('添加到队列')),
          const PopupMenuItem(value: 'add_to_favorites', child: Text('收藏')),
          const PopupMenuItem(value: 'add_to_playlist', child: Text('添加到歌单')),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'manual_scrape', child: Text('手动刮削')),
        ],
      ),
    );
  }

  Future<void> _playTrack(BuildContext context, WidgetRef ref) async {
    logger.i('_CompactMusicTile._playTrack: 开始播放 ${track.name}');

    // 通过 sourceId 从已连接的源中获取适配器
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[track.sourceId];
    if (connection == null || connection.status != SourceStatus.connected) {
      logger.e('_CompactMusicTile._playTrack: 源未连接 sourceId=${track.sourceId}');
      if (context.mounted) {
        context.showWarningToast('源未连接，请先连接到 NAS');
      }
      return;
    }
    final adapter = connection.adapter;

    try {
      logger.d('_CompactMusicTile._playTrack: 获取文件 URL: ${track.path}');
      final url = await adapter.fileSystem.getFileUrl(track.path);
      logger.d('_CompactMusicTile._playTrack: 获取到 URL: $url');

      final musicItem = MusicItem.fromFileItem(
        track.file,
        url,
        sourceId: track.sourceId,
        title: track.title,
        artist: track.artist,
        album: track.album,
        durationMs: track.duration,
        trackNumber: track.trackNumber,
        year: track.year,
        genre: track.genre,
        coverData: track.coverData,
        coverUrl: track.coverFileUrl,
      );
      logger.d('_CompactMusicTile._playTrack: 创建 MusicItem 成功');

      if (!context.mounted) {
        logger.w('_CompactMusicTile._playTrack: context 已卸载');
        return;
      }

      // 先播放当前曲目
      ref.read(playQueueProvider.notifier).setQueue([musicItem]);
      ref.read(musicPlayerControllerProvider.notifier).updateCurrentIndex(0);
      logger.d('_CompactMusicTile._playTrack: 调用播放器播放');
      await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);
      logger.i('_CompactMusicTile._playTrack: 播放成功，跳转到播放页');

      // 导航到播放器页面
      if (!context.mounted) return;
      AppError.fireAndForget(MusicPlayerPage.open(context), action: 'musicList.openMusicPlayerPage');

      // 在后台构建完整播放队列
      if (allTracks != null && allTracks!.isNotEmpty) {
        await _buildPlayQueue(ref, connections, trackIndex ?? 0);
      }
    } on Exception catch (e, stackTrace) {
      logger.e('_CompactMusicTile._playTrack: 播放失败', e, stackTrace);
      if (context.mounted) {
        context.showErrorToast('播放失败: $e');
      }
    }
  }

  /// 在后台构建播放队列
  Future<void> _buildPlayQueue(
    WidgetRef ref,
    Map<String, SourceConnection> connections,
    int currentIndex,
  ) async {
    if (allTracks == null) return;

    try {
      // 构建播放队列（最多50首，以当前曲目为中心）
      const queueSize = 50;
      int startIndex;
      int endIndex;

      if (allTracks!.length <= queueSize) {
        startIndex = 0;
        endIndex = allTracks!.length;
      } else {
        // 以当前曲目为中心
        final halfSize = queueSize ~/ 2;
        startIndex = (currentIndex - halfSize).clamp(0, allTracks!.length - queueSize);
        endIndex = (startIndex + queueSize).clamp(0, allTracks!.length);
      }

      final queueTracks = allTracks!.sublist(startIndex, endIndex);
      final queue = <MusicItem>[];
      var newCurrentIndex = 0;

      for (var i = 0; i < queueTracks.length; i++) {
        final t = queueTracks[i];
        final conn = connections[t.sourceId];
        if (conn == null || conn.status != SourceStatus.connected) continue;
        final trackUrl = await conn.adapter.fileSystem.getFileUrl(t.path);
        final item = MusicItem.fromFileItem(
          t.file,
          trackUrl,
          sourceId: t.sourceId,
          title: t.title,
          artist: t.artist,
          album: t.album,
          durationMs: t.duration,
          coverData: t.coverData,
          coverUrl: t.coverFileUrl,
        );
        queue.add(item);
        if (t.path == track.path) {
          newCurrentIndex = queue.length - 1;
        }
      }

      // 更新播放队列
      ref.read(playQueueProvider.notifier).setQueue(queue);
      ref.read(musicPlayerControllerProvider.notifier).updateCurrentIndex(newCurrentIndex);
      logger.d('_CompactMusicTile._buildPlayQueue: 队列构建完成，共 ${queue.length} 首');
    } on Exception catch (e) {
      logger.w('_CompactMusicTile._buildPlayQueue: 构建播放队列失败: $e');
    }
  }

  Future<void> _handleAction(BuildContext context, WidgetRef ref, String action) async {
    logger.i('_CompactMusicTile._handleAction: action=$action, track=${track.name}');

    // 通过 sourceId 从已连接的源中获取适配器
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[track.sourceId];
    if (connection == null || connection.status != SourceStatus.connected) {
      logger.e('_CompactMusicTile._handleAction: 源未连接 sourceId=${track.sourceId}');
      if (context.mounted) {
        context.showWarningToast('源未连接，请先连接到 NAS');
      }
      return;
    }
    final adapter = connection.adapter;

    try {
      final url = await adapter.fileSystem.getFileUrl(track.path);
      final musicItem = MusicItem.fromFileItem(
        track.file,
        url,
        sourceId: track.sourceId,
        title: track.title,
        artist: track.artist,
        album: track.album,
        durationMs: track.duration,
        coverData: track.coverData,
        coverUrl: track.coverFileUrl,
      );

      switch (action) {
      case 'play_next':
        final queue = ref.read(playQueueProvider);
        final playerState = ref.read(musicPlayerControllerProvider);
        if (queue.isEmpty) {
          await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);
        } else {
          final insertIndex = playerState.currentIndex + 1;
          final newQueue = [...queue];
          newQueue.insert(insertIndex.clamp(0, newQueue.length), musicItem);
          ref.read(playQueueProvider.notifier).setQueue(newQueue);
          if (context.mounted) {
            context.showSuccessToast('已添加到下一首播放');
          }
        }
      case 'add_to_queue':
        ref.read(playQueueProvider.notifier).addToQueue(musicItem);
        if (context.mounted) {
          context.showSuccessToast('已添加到播放队列');
        }
      case 'add_to_favorites':
        final isFav = await ref.read(musicFavoritesProvider.notifier).toggleFavorite(musicItem);
        if (context.mounted) {
          context.showSuccessToast(isFav ? '已添加到收藏' : '已取消收藏');
        }
      case 'add_to_playlist':
        if (context.mounted) {
          // 使用 sourceId_path 格式唯一标识歌曲
          final trackId = '${track.sourceId}_${track.path}';
          _showAddToPlaylistSheet(context, ref, trackId);
        }
      case 'manual_scrape':
        if (context.mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ManualMusicScraperPage(
                music: musicItem,
                fileSystem: adapter.fileSystem,
              ),
            ),
          );
        }
      }
    } on Exception catch (e, stackTrace) {
      logger.e('_CompactMusicTile._handleAction: 操作失败', e, stackTrace);
      if (context.mounted) {
        context.showErrorToast('操作失败: $e');
      }
    }
  }

  void _showAddToPlaylistSheet(BuildContext context, WidgetRef ref, String trackPath) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final playlistState = ref.read(playlistProvider);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '添加到歌单',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.add_rounded, color: AppColors.primary),
              ),
              title: Text(
                '新建歌单',
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _showCreatePlaylistSheet(context, ref, trackPath);
              },
            ),
            if (playlistState.playlists.isNotEmpty) ...[
              const Divider(),
              ...playlistState.playlists.take(5).map((playlist) => ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.7),
                          AppColors.secondary.withValues(alpha: 0.7),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.queue_music_rounded, color: Colors.white, size: 20),
                  ),
                  title: Text(
                    playlist.name,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  ),
                  subtitle: Text('${playlist.trackCount} 首歌曲'),
                  onTap: () async {
                    await ref.read(playlistProvider.notifier).addToPlaylist(playlist.id, trackPath);
                    if (sheetContext.mounted) {
                      Navigator.pop(sheetContext);
                      context.showSuccessToast('已添加到歌单"${playlist.name}"');
                    }
                  },
                )),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showCreatePlaylistSheet(BuildContext context, WidgetRef ref, String trackPath) {
    final controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        title: Text(
          '新建歌单',
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '输入歌单名称',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                await ref.read(playlistProvider.notifier).createPlaylist(
                      name: name,
                      initialTracks: [trackPath],
                    );
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已添加到新歌单"$name"'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('创建并添加'),
          ),
        ],
      ),
    );
  }
}

/// 全部播放按钮
class _PlayAllButton extends ConsumerWidget {
  const _PlayAllButton({
    required this.tracks,
    required this.isDark,
  });

  final List<MusicFileWithSource> tracks;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ElevatedButton.icon(
      onPressed: () => _playAll(context, ref),
      icon: const Icon(Icons.play_arrow_rounded, size: 20),
      label: const Text('播放全部'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );

  Future<void> _playAll(BuildContext context, WidgetRef ref) async {
    if (tracks.isEmpty) return;

    final connections = ref.read(activeConnectionsProvider);

    // 转换所有曲目
    final musicItems = <MusicItem>[];
    for (final track in tracks) {
      final connection = connections[track.sourceId];
      if (connection == null || connection.status != SourceStatus.connected) {
        continue; // 跳过未连接源的歌曲
      }
      final url = await connection.adapter.fileSystem.getFileUrl(track.path);
      musicItems.add(MusicItem.fromFileItem(
        track.file,
        url,
        sourceId: track.sourceId,
        title: track.title,
        artist: track.artist,
        album: track.album,
        durationMs: track.duration,
        coverData: track.coverData,
        coverUrl: track.coverFileUrl,
      ));
    }

    if (musicItems.isEmpty) return;

    // 设置播放队列并播放第一首
    ref.read(playQueueProvider.notifier).setQueue(musicItems);
    await ref.read(musicPlayerControllerProvider.notifier).play(musicItems.first);

    if (context.mounted) {
      Navigator.of(context).pop();
      await MusicPlayerPage.open(context);
    }
  }
}

/// 空状态视图
Widget _buildEmptyView(String message, IconData icon, bool isDark) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 40, color: AppColors.primary),
        ),
        const SizedBox(height: 16),
        Text(
          message,
          style: TextStyle(
            fontSize: 16,
            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
          ),
        ),
      ],
    ),
  );

/// 根据索引获取渐变色
List<Color> _getGradientColorsForIndex(int index) {
  const colorPairs = [
    [Color(0xFF667eea), Color(0xFF764ba2)], // 紫色渐变
    [Color(0xFFf093fb), Color(0xFFf5576c)], // 粉红渐变
    [Color(0xFF4facfe), Color(0xFF00f2fe)], // 蓝色渐变
    [Color(0xFF43e97b), Color(0xFF38f9d7)], // 绿色渐变
    [Color(0xFFfa709a), Color(0xFFfee140)], // 橙粉渐变
    [Color(0xFF30cfd0), Color(0xFF330867)], // 青紫渐变
    [Color(0xFFa8edea), Color(0xFFfed6e3)], // 浅色渐变
    [Color(0xFFff9a9e), Color(0xFFfecfef)], // 粉红浅色
  ];
  return colorPairs[index % colorPairs.length];
}
