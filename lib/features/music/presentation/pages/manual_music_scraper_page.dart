import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/music/data/services/live_activity_service.dart';
import 'package:my_nas/features/music/data/services/music_cover_cache_service.dart';
import 'package:my_nas/features/music/data/services/music_database_service.dart';
import 'package:my_nas/features/music/data/services/music_favorites_service.dart';
import 'package:my_nas/features/music/data/services/music_tag_writer_service.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_result.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/presentation/pages/music_list_page.dart';
import 'package:my_nas/features/music/presentation/providers/lyric_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_favorites_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_scraper_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_tag_write_queue_provider.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/main.dart' show audioHandler;
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/widgets/adaptive_image.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';
import 'package:path/path.dart' as p;

/// 手动音乐刮削页面
class ManualMusicScraperPage extends ConsumerStatefulWidget {
  const ManualMusicScraperPage({
    super.key,
    required this.music,
    this.fileSystem,
  });

  final MusicItem music;
  final NasFileSystem? fileSystem;

  @override
  ConsumerState<ManualMusicScraperPage> createState() => _ManualMusicScraperPageState();
}

class _ManualMusicScraperPageState extends ConsumerState<ManualMusicScraperPage>
    with ConsumerTabBarVisibilityMixin {
  // 搜索控制器
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _artistController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // 状态
  bool _isSearching = false;
  bool _isLoadingDetail = false;
  bool _isScraping = false;
  String? _errorMessage;

  // 搜索结果（统一列表，按时长匹配度排序）
  List<MusicScraperItem> _searchResults = [];
  int _totalResultCount = 0;

  // 选中的项
  MusicScraperItem? _selectedItem;
  MusicScraperDetail? _selectedDetail;
  LyricScraperResult? _selectedLyrics;
  CoverScraperResult? _selectedCover;

  // 刮削选项
  bool _downloadCover = true;
  bool _downloadLyrics = true;
  bool _writeToFile = true;

  // 标签写入服务
  final _tagWriter = MusicTagWriterService();
  SupportedAudioFormat? _audioFormat;

  /// 当前音乐的时长（毫秒）
  int get _musicDurationMs => widget.music.duration?.inMilliseconds ?? 0;

  /// 检查是否已有封面
  bool get _hasCover =>
      widget.music.coverUrl != null || widget.music.coverData != null;

  /// 检查是否已有歌词
  bool get _hasLyrics =>
      widget.music.lyrics != null && widget.music.lyrics!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    hideTabBar();
    _audioFormat = _tagWriter.getFormat(widget.music.path);

    // 如果已有封面/歌词，默认不下载（但用户可以勾选覆盖）
    if (_hasCover) {
      _downloadCover = false;
    }
    if (_hasLyrics) {
      _downloadLyrics = false;
    }

    _initFromMusic();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _initFromMusic() {
    _titleController.text = widget.music.displayTitle;
    _artistController.text = widget.music.displayArtist;

    // 自动搜索
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  Future<void> _search() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _searchResults.clear();
      _totalResultCount = 0;
      _clearSelection();
    });

    try {
      final manager = ref.read(musicScraperManagerProvider);
      await manager.init();

      final results = await manager.search(
        title,
        artist: _artistController.text.trim().isNotEmpty
            ? _artistController.text.trim()
            : null,
        limit: 30, // 每个源最多30个结果
      );

      // 合并所有结果到统一列表并记录每个源的结果数量
      final allItems = <MusicScraperItem>[];
      final sourceStats = <String, int>{};
      for (final result in results) {
        allItems.addAll(result.items);
        final sourceName = result.source.displayName;
        sourceStats[sourceName] = result.items.length;
      }
      debugPrint('[ManualScraper] 搜索结果统计: $sourceStats, 总计: ${allItems.length}');
      debugPrint('[ManualScraper] 当前音乐时长: ${_musicDurationMs}ms (${widget.music.duration})');

      // 获取刮削源优先级映射
      final sources = await manager.getSources();
      final sourcePriorities = <MusicScraperType, int>{};
      for (final source in sources) {
        sourcePriorities[source.type] = source.priority;
      }

      // 按时长匹配度排序（同等时长差时按刮削源优先级排序）
      _sortByDurationMatch(allItems, sourcePriorities);

      // 打印排序后前10个结果的来源和时长差
      if (allItems.isNotEmpty) {
        final first10 = allItems.take(10).map((e) {
          final diff = e.durationMs != null ? (e.durationMs! - _musicDurationMs).abs() : 999999999;
          return '${e.source.displayName}:${e.durationMs ?? 0}ms(diff=$diff)';
        }).join(', ');
        debugPrint('[ManualScraper] 排序后前10: $first10');
      }

      setState(() {
        _searchResults = allItems;
        _totalResultCount = allItems.length;
        _isSearching = false;
      });
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'ManualMusicScraperPage._search');
      setState(() {
        _errorMessage = context.l10n.musicManualScraperSearchFailed(e);
        _isSearching = false;
      });
    }
  }

  /// 按时长匹配度排序（混合所有来源）
  /// [sourcePriorities] 刮削源优先级映射（优先级数值越小越优先）
  void _sortByDurationMatch(
    List<MusicScraperItem> items,
    Map<MusicScraperType, int> sourcePriorities,
  ) {
    // 如果播放歌曲有时长信息，按时长差值排序
    // 否则只按来源交替排序
    final hasMusicDuration = _musicDurationMs > 0;

    items.sort((a, b) {
      if (hasMusicDuration) {
        // 1. 首先按时长差值排序（主要排序条件）
        final diffA = _getDurationDiff(a);
        final diffB = _getDurationDiff(b);
        if (diffA != diffB) {
          return diffA.compareTo(diffB);
        }
      } else {
        // 没有播放歌曲时长时，有时长的优先
        final hasA = a.durationMs != null && a.durationMs! > 0;
        final hasB = b.durationMs != null && b.durationMs! > 0;
        if (hasA != hasB) {
          return hasA ? -1 : 1;
        }
      }

      // 2. 时长差值相同时，按刮削源优先级排序（用户设置的顺序）
      // 优先级数值越小越优先，未配置的源使用 999 作为默认值
      final priorityA = sourcePriorities[a.source] ?? 999;
      final priorityB = sourcePriorities[b.source] ?? 999;
      if (priorityA != priorityB) {
        return priorityA.compareTo(priorityB);
      }

      // 3. 同来源同时长时，按标题排序
      return a.title.compareTo(b.title);
    });
  }

  /// 获取时长差值（毫秒）
  int _getDurationDiff(MusicScraperItem item) {
    if (item.durationMs == null || item.durationMs == 0) {
      return 999999999; // 无时长的排在最后
    }
    return (item.durationMs! - _musicDurationMs).abs();
  }

  /// 计算匹配度百分比
  double _getMatchPercent(MusicScraperItem item) {
    if (_musicDurationMs <= 0 || item.durationMs == null || item.durationMs == 0) {
      return 0;
    }
    final diff = _getDurationDiff(item);
    // 差值在5秒以内视为100%匹配，超过60秒视为0%匹配
    if (diff <= 5000) return 100;
    if (diff >= 60000) return 0;
    return ((60000 - diff) / 550).clamp(0, 100);
  }

  void _clearSelection() {
    _selectedItem = null;
    _selectedDetail = null;
    _selectedLyrics = null;
    _selectedCover = null;
  }

  Future<void> _selectItem(MusicScraperItem item) async {
    // 如果点击已选中的项，取消选中
    if (_selectedItem?.externalId == item.externalId) {
      setState(_clearSelection);
      return;
    }

    setState(() {
      _selectedItem = item;
      _isLoadingDetail = true;
      _errorMessage = null;
    });

    try {
      final manager = ref.read(musicScraperManagerProvider);

      // 获取详情
      final detail = await manager.getDetail(item.externalId, item.source);

      // 获取歌词
      LyricScraperResult? lyrics;
      if (item.source.supportsLyrics) {
        final sources = await manager.getSources();
        final source = sources.where((s) => s.type == item.source).firstOrNull;
        if (source != null) {
          final scraper = await manager.getScraper(source.id);
          if (scraper != null) {
            lyrics = await scraper.getLyrics(item.externalId);
          }
        }
      }

      // 获取封面
      CoverScraperResult? cover;
      if (item.coverUrl != null) {
        cover = CoverScraperResult(
          source: item.source,
          coverUrl: item.coverUrl!,
        );
      }

      setState(() {
        _selectedDetail = detail;
        _selectedLyrics = lyrics;
        _selectedCover = cover;
        _isLoadingDetail = false;
      });
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'ManualMusicScraperPage._selectItem');
      setState(() {
        _errorMessage = context.l10n.musicManualScraperGetDetailsFailed(e);
        _isLoadingDetail = false;
      });
    }
  }

  Future<void> _confirmAndScrape() async {
    if (_selectedDetail == null && _selectedCover == null && _selectedLyrics == null) {
      return;
    }

    // 获取文件系统
    var fileSystem = widget.fileSystem;
    if (fileSystem == null && widget.music.sourceId != null) {
      final connections = ref.read(activeConnectionsProvider);
      final connection = connections[widget.music.sourceId];
      if (connection?.status == SourceStatus.connected) {
        fileSystem = connection!.adapter.fileSystem;
      }
    }

    if (fileSystem == null) {
      context.showErrorToast(context.l10n.musicManualScraperFileSystemUnavailable);
      return;
    }

    setState(() => _isScraping = true);

    try {
      final musicDir = p.dirname(widget.music.path);
      final baseName = p.basenameWithoutExtension(widget.music.path);

      Uint8List? coverData;
      String? coverMimeType;

      // 下载封面
      if (_downloadCover && _selectedCover != null) {
        final result = await _downloadCoverData();
        coverData = result.$1;
        coverMimeType = result.$2;

        await _saveCoverFile(fileSystem, musicDir, baseName, coverData);

        if (coverData != null) {
          await _syncCoverToLocalCache(coverData);
        }
      }

      // 下载歌词
      if (_downloadLyrics && (_selectedLyrics?.hasLyrics ?? false)) {
        await _downloadLyricsToFile(fileSystem, musicDir, baseName);

        final currentMusic = ref.read(currentMusicProvider);
        if (currentMusic?.id == widget.music.id) {
          AppError.fireAndForget(
            ref.read(currentLyricProvider.notifier).loadLyrics(widget.music),
            action: 'reloadLyricsAfterScrape',
          );
        }
      }

      _updateCurrentMusicMetadata(coverData);

      if (_selectedDetail != null) {
        await _syncMetadataToDatabase();
      }

      if (_writeToFile && _audioFormat != null && _selectedDetail != null) {
        _queueTagWrite(coverData, coverMimeType);
      }

      // 更新收藏和播放历史中的元数据
      await _syncToFavoritesAndHistory(coverData);

      if (!mounted) return;

      context.showSuccessToast(context.l10n.musicManualScraperCompletedToast);
      Navigator.pop(context, true);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'ManualMusicScraperPage._confirmAndScrape');
      if (mounted) {
        context.showErrorToast(context.l10n.musicManualScraperScrapingFailed(e));
      }
    } finally {
      if (mounted) {
        setState(() => _isScraping = false);
      }
    }
  }

  Future<void> _syncCoverToLocalCache(Uint8List coverData) async {
    final sourceId = widget.music.sourceId;
    if (sourceId == null) return;

    try {
      final coverCache = MusicCoverCacheService();
      await coverCache.init();

      final uniqueKey = '${sourceId}_${widget.music.path}';
      final localCoverPath = await coverCache.saveCover(uniqueKey, coverData);

      if (localCoverPath == null) return;

      final db = MusicDatabaseService();
      await db.init();

      final existing = await db.get(sourceId, widget.music.path);
      if (existing != null) {
        await db.upsert(existing.copyWith(
          coverPath: localCoverPath,
          title: (existing.title == null || existing.title!.isEmpty)
              ? _selectedDetail?.title
              : existing.title,
          artist: (existing.artist == null || existing.artist!.isEmpty)
              ? _selectedDetail?.artist
              : existing.artist,
          album: (existing.album == null || existing.album!.isEmpty)
              ? _selectedDetail?.album
              : existing.album,
          year: existing.year ?? _selectedDetail?.year,
          trackNumber: existing.trackNumber ?? _selectedDetail?.trackNumber,
          genre: (existing.genre == null || existing.genre!.isEmpty)
              ? _selectedDetail?.genres?.join(', ')
              : existing.genre,
          lastUpdated: DateTime.now(),
        ));
      } else {
        await db.upsert(MusicTrackEntity(
          sourceId: sourceId,
          filePath: widget.music.path,
          fileName: widget.music.name,
          title: _selectedDetail?.title ?? widget.music.title,
          artist: _selectedDetail?.artist ?? widget.music.artist,
          album: _selectedDetail?.album ?? widget.music.album,
          year: _selectedDetail?.year,
          trackNumber: _selectedDetail?.trackNumber,
          genre: _selectedDetail?.genres?.join(', '),
          coverPath: localCoverPath,
          duration: widget.music.duration?.inMilliseconds,
          lastUpdated: DateTime.now(),
        ));
      }

      // 如果当前正在播放这首歌，更新 Now Playing 和灵动岛封面
      final currentMusic = ref.read(currentMusicProvider);
      if (currentMusic?.id == widget.music.id) {
        // 更新 Now Playing / 锁屏控制中心的封面
        await audioHandler.updateArtwork(coverData);

        // 更新灵动岛的封面（仅 iOS）
        if (Platform.isIOS) {
          final updatedMusic = currentMusic!.copyWith(
            coverData: coverData.toList(),
            coverUrl: 'file://$localCoverPath',
          );
          await LiveActivityService().updateCoverImage(updatedMusic, coverData);
        }

        // 更新播放队列中的封面
        ref.read(playQueueProvider.notifier).updateTrackCover(
          widget.music.id,
          coverData: coverData,
          coverUrl: 'file://$localCoverPath',
        );
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '同步封面到本地缓存失败');
    }
  }

  void _updateCurrentMusicMetadata(Uint8List? coverData) {
    final currentMusic = ref.read(currentMusicProvider);
    if (currentMusic?.id != widget.music.id) return;

    ref.read(currentMusicProvider.notifier).state = currentMusic!.copyWith(
      title: (currentMusic.title == null || currentMusic.title!.isEmpty)
          ? _selectedDetail?.title
          : currentMusic.title,
      artist: (currentMusic.artist == null || currentMusic.artist!.isEmpty)
          ? _selectedDetail?.artist
          : currentMusic.artist,
      album: (currentMusic.album == null || currentMusic.album!.isEmpty)
          ? _selectedDetail?.album
          : currentMusic.album,
      year: currentMusic.year ?? _selectedDetail?.year,
      trackNumber: currentMusic.trackNumber ?? _selectedDetail?.trackNumber,
      genre: (currentMusic.genre == null || currentMusic.genre!.isEmpty)
          ? _selectedDetail?.genres?.join(', ')
          : currentMusic.genre,
      lyrics: _selectedLyrics?.lrcContent ?? _selectedLyrics?.plainText ?? currentMusic.lyrics,
      coverData: coverData?.toList() ?? currentMusic.coverData,
    );

    ref.read(playQueueProvider.notifier).updateTrackMetadata(
      widget.music.id,
      title: _selectedDetail?.title,
      artist: _selectedDetail?.artist,
      album: _selectedDetail?.album,
      year: _selectedDetail?.year,
      trackNumber: _selectedDetail?.trackNumber,
      genre: _selectedDetail?.genres?.join(', '),
    );
  }

  Future<void> _syncMetadataToDatabase() async {
    final sourceId = widget.music.sourceId;
    if (sourceId == null || _selectedDetail == null) return;

    try {
      final db = MusicDatabaseService();
      await db.init();

      final existing = await db.get(sourceId, widget.music.path);
      if (existing != null) {
        final updated = existing.copyWith(
          title: (existing.title == null || existing.title!.isEmpty)
              ? _selectedDetail?.title
              : existing.title,
          artist: (existing.artist == null || existing.artist!.isEmpty)
              ? _selectedDetail?.artist
              : existing.artist,
          album: (existing.album == null || existing.album!.isEmpty)
              ? _selectedDetail?.album
              : existing.album,
          year: existing.year ?? _selectedDetail?.year,
          trackNumber: existing.trackNumber ?? _selectedDetail?.trackNumber,
          genre: (existing.genre == null || existing.genre!.isEmpty)
              ? _selectedDetail?.genres?.join(', ')
              : existing.genre,
          lastUpdated: DateTime.now(),
        );
        await db.upsert(updated);
      } else {
        await db.upsert(MusicTrackEntity(
          sourceId: sourceId,
          filePath: widget.music.path,
          fileName: widget.music.name,
          title: _selectedDetail?.title ?? widget.music.title,
          artist: _selectedDetail?.artist ?? widget.music.artist,
          album: _selectedDetail?.album ?? widget.music.album,
          year: _selectedDetail?.year,
          trackNumber: _selectedDetail?.trackNumber,
          genre: _selectedDetail?.genres?.join(', '),
          duration: widget.music.duration?.inMilliseconds,
          lastUpdated: DateTime.now(),
        ));
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '同步元数据到数据库失败');
    }
  }

  /// 同步更新到收藏和播放历史
  Future<void> _syncToFavoritesAndHistory(Uint8List? coverData) async {
    try {
      // 构建封面 URL
      String? coverUrl;
      if (coverData != null) {
        final sourceId = widget.music.sourceId;
        if (sourceId != null) {
          final coverCache = MusicCoverCacheService();
          await coverCache.init();
          final uniqueKey = '${sourceId}_${widget.music.path}';
          final localPath = await coverCache.getCoverPath(uniqueKey);
          if (localPath != null) {
            coverUrl = 'file://$localPath';
          }
        }
      }

      // 更新收藏和播放历史中的元数据
      await MusicFavoritesService().updateMetadata(
        widget.music.path,
        title: _selectedDetail?.title,
        artist: _selectedDetail?.artist,
        album: _selectedDetail?.album,
        coverUrl: coverUrl,
      );

      // 刷新 provider 使 UI 更新（必须 await 确保刷新完成后再关闭页面）
      await ref.read(musicFavoritesProvider.notifier).refresh();
      await ref.read(musicHistoryProvider.notifier).refresh();

      // 刷新音乐列表中该曲目的元数据
      final sourceId = widget.music.sourceId;
      if (sourceId != null) {
        await ref.read(musicListProvider.notifier).refreshTrackMetadata(
          sourceId,
          widget.music.path,
        );
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '同步到收藏和播放历史失败');
    }
  }

  void _queueTagWrite(Uint8List? coverData, String? coverMimeType) {
    final writeQueue = ref.read(musicTagWriteQueueProvider);

    final tagData = MusicTagData(
      title: _selectedDetail?.title,
      artist: _selectedDetail?.artist,
      album: _selectedDetail?.album,
      albumArtist: _selectedDetail?.albumArtist,
      year: _selectedDetail?.year,
      trackNumber: _selectedDetail?.trackNumber,
      discNumber: _selectedDetail?.discNumber,
      genre: _selectedDetail?.genres?.join(', '),
      lyrics: _selectedLyrics?.lrcContent ?? _selectedLyrics?.plainText,
    );

    writeQueue.addTask(
      musicPath: widget.music.path,
      sourceId: widget.music.sourceId,
      tagData: tagData,
      coverData: coverData,
      coverMimeType: coverMimeType,
    );
  }

  Future<(Uint8List?, String?)> _downloadCoverData() async {
    if (_selectedCover == null) return (null, null);

    try {
      final dio = Dio();
      final response = await dio.get<List<int>>(
        _selectedCover!.coverUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.data == null) return (null, null);

      final coverData = Uint8List.fromList(response.data!);
      final mimeType = _selectedCover!.coverUrl.contains('.png') ? 'image/png' : 'image/jpeg';

      return (coverData, mimeType);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '下载封面数据失败');
      return (null, null);
    }
  }

  Future<void> _saveCoverFile(
    NasFileSystem fileSystem,
    String musicDir,
    String baseName,
    Uint8List? coverData,
  ) async {
    if (coverData == null || _selectedCover == null) return;

    try {
      final ext = _selectedCover!.coverUrl.contains('.png') ? 'png' : 'jpg';

      final folderCoverPath = p.join(musicDir, 'folder.$ext');
      var exists = false;
      try {
        await fileSystem.getFileInfo(folderCoverPath);
        exists = true;
      } on Exception {
        exists = false;
      }

      final coverPath = exists
          ? p.join(musicDir, '$baseName-cover.$ext')
          : folderCoverPath;

      await fileSystem.writeFile(coverPath, coverData);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '保存封面文件失败');
    }
  }

  Future<void> _downloadLyricsToFile(
    NasFileSystem fileSystem,
    String musicDir,
    String baseName,
  ) async {
    if (_selectedLyrics == null || !_selectedLyrics!.hasLyrics) return;

    try {
      final lrcContent = _selectedLyrics!.lrcContent ?? _selectedLyrics!.plainText ?? '';
      if (lrcContent.isEmpty) return;

      final lrcPath = p.join(musicDir, '$baseName.lrc');
      final utf8Bytes = const Utf8Encoder().convert(lrcContent);
      await fileSystem.writeFile(lrcPath, Uint8List.fromList(utf8Bytes));
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '下载歌词失败');
    }
  }

  /// 格式化时长差值
  String _formatDurationDiff(MusicScraperItem item) {
    if (_musicDurationMs <= 0 || item.durationMs == null || item.durationMs == 0) {
      return '';
    }
    final diffMs = item.durationMs! - _musicDurationMs;
    final diffSec = diffMs ~/ 1000;
    if (diffSec.abs() < 1) return '±0s';
    return diffSec > 0 ? '+${diffSec}s' : '${diffSec}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: const RoundedBackButton(),
        title: Text(context.l10n.musicManualScraperPageTitle),
        actions: [
          if (_totalResultCount > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  context.l10n.musicManualScraperResultCount(_totalResultCount),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // 文件信息（紧凑展示）
          _buildCompactFileInfo(theme, isDark),

          // 搜索栏
          _buildSearchBar(theme, isDark),

          // 内容区域
          Expanded(child: _buildSearchResults(theme, isDark)),

          // 选中项预览和操作
          if (_selectedItem != null) _buildSelectionPanel(theme, isDark),
        ],
      ),
    );
  }

  Widget _buildCompactFileInfo(ThemeData theme, bool isDark) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: isDark
          ? AppColors.darkSurface
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      border: Border(
        bottom: BorderSide(
          color: isDark ? AppColors.darkOutline : theme.dividerColor,
          width: 0.5,
        ),
      ),
    ),
    child: Row(
      children: [
        // 封面
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: AppColors.fileAudio.withValues(alpha: 0.1),
          ),
          child: widget.music.coverUrl != null || widget.music.coverData != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: widget.music.coverData != null
                      ? Image.memory(
                          Uint8List.fromList(widget.music.coverData!),
                          fit: BoxFit.cover,
                        )
                      : AdaptiveImage(
                          imageUrl: widget.music.coverUrl!,
                          fit: BoxFit.cover,
                        ),
                )
              : Icon(
                  Icons.music_note_rounded,
                  color: AppColors.fileAudio,
                  size: 22,
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.music.displayTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (widget.music.displayArtist.isNotEmpty) ...[
                    Flexible(
                      child: Text(
                        widget.music.displayArtist,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? AppColors.darkOnSurfaceVariant
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (_musicDurationMs > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _formatDuration(_musicDurationMs),
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildSearchBar(ThemeData theme, bool isDark) => Padding(
    padding: const EdgeInsets.all(12),
    child: Row(
      children: [
        // 标题搜索框
        Expanded(
          flex: 3,
          child: TextField(
            controller: _titleController,
            decoration: InputDecoration(
              hintText: context.l10n.musicManualScraperSongHint,
              prefixIcon: const Icon(Icons.music_note_outlined, size: 20),
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
            onSubmitted: (_) => _search(),
          ),
        ),
        const SizedBox(width: 8),
        // 艺术家过滤
        Expanded(
          flex: 2,
          child: TextField(
            controller: _artistController,
            decoration: InputDecoration(
              hintText: context.l10n.musicManualScraperArtistHint,
              prefixIcon: Icon(Icons.person_outline, size: 20),
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
            onSubmitted: (_) => _search(),
          ),
        ),
        const SizedBox(width: 8),
        // 搜索按钮
        SizedBox(
          height: 42,
          child: FilledButton(
            onPressed: _isSearching ? null : _search,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: _isSearching
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.search_rounded, size: 20),
          ),
        ),
      ],
    ),
  );

  Widget _buildSearchResults(ThemeData theme, bool isDark) {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _search, child: Text(context.l10n.musicManualScraperRetryButton)),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: isDark ? AppColors.darkOnSurfaceVariant : theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.musicManualScraperNoResults,
              style: theme.textTheme.titleMedium?.copyWith(
                color: isDark ? AppColors.darkOnSurfaceVariant : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.musicManualScraperAdjustKeywords,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark ? AppColors.darkOnSurfaceVariant : theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          final item = _searchResults[index];
          final isSelected = _selectedItem?.externalId == item.externalId;
          return _buildResultCard(item, isSelected, theme, isDark);
        },
      ),
    );
  }

  Widget _buildResultCard(MusicScraperItem item, bool isSelected, ThemeData theme, bool isDark) {
    final matchPercent = _getMatchPercent(item);
    final durationDiff = _formatDurationDiff(item);
    final hasHighMatch = matchPercent >= 90;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: isSelected ? 4 : 1,
      color: isSelected
          ? (isDark ? AppColors.primary.withValues(alpha: 0.15) : AppColors.primary.withValues(alpha: 0.08))
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isSelected
            ? BorderSide(color: AppColors.primary, width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _selectItem(item),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              // 封面
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: item.source.themeColor.withValues(alpha: 0.1),
                ),
                child: Stack(
                  children: [
                    if (item.coverUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: AdaptiveImage(
                          imageUrl: item.coverUrl!,
                          fit: BoxFit.cover,
                          width: 52,
                          height: 52,
                        ),
                      )
                    else
                      Center(
                        child: Icon(Icons.music_note, color: item.source.themeColor, size: 24),
                      ),
                    // 来源角标
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: item.source.themeColor,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(6),
                            bottomRight: Radius.circular(6),
                          ),
                        ),
                        child: Icon(item.source.icon, size: 10, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // 艺术家 / 专辑
                    Text(
                      [
                        if (item.artist != null) item.artist,
                        if (item.album != null) item.album,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? AppColors.darkOnSurfaceVariant : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // 底部标签行
                    Row(
                      children: [
                        // 来源
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: item.source.themeColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            item.source.displayName,
                            style: TextStyle(
                              fontSize: 10,
                              color: item.source.themeColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // 时长
                        if (item.durationText.isNotEmpty)
                          Text(
                            item.durationText,
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? Colors.grey[500] : Colors.grey[600],
                            ),
                          ),
                        // 歌词支持
                        if (item.source.supportsLyrics) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.lyrics_rounded,
                            size: 12,
                            color: isDark ? Colors.cyan[300] : Colors.cyan[700],
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // 右侧：匹配度指示器
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (matchPercent > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: hasHighMatch
                            ? AppColors.success.withValues(alpha: 0.15)
                            : (matchPercent >= 50
                                ? Colors.orange.withValues(alpha: 0.15)
                                : Colors.grey.withValues(alpha: 0.15)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '${matchPercent.toInt()}%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: hasHighMatch
                                  ? AppColors.success
                                  : (matchPercent >= 50 ? Colors.orange : Colors.grey),
                            ),
                          ),
                          if (durationDiff.isNotEmpty)
                            Text(
                              durationDiff,
                              style: TextStyle(
                                fontSize: 9,
                                color: hasHighMatch
                                    ? AppColors.success
                                    : (matchPercent >= 50 ? Colors.orange : Colors.grey),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ] else
                    Icon(
                      Icons.chevron_right,
                      color: isDark ? Colors.grey[600] : Colors.grey[400],
                    ),
                  if (isSelected)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Icon(
                        Icons.check_circle,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionPanel(ThemeData theme, bool isDark) {
    final hasContent = _selectedDetail != null || _selectedCover != null || _selectedLyrics != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkOutline : theme.dividerColor,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 加载中
            if (_isLoadingDetail)
              const LinearProgressIndicator()
            else if (hasContent)
              // 选项和按钮
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  children: [
                    // 选中项信息
                    Row(
                      children: [
                        // 封面预览
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: _selectedItem?.source.themeColor.withValues(alpha: 0.1),
                          ),
                          child: _selectedCover?.coverUrl != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: AdaptiveImage(
                                    imageUrl: _selectedCover!.coverUrl,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Icon(
                                  Icons.album,
                                  color: _selectedItem?.source.themeColor,
                                ),
                        ),
                        const SizedBox(width: 12),
                        // 信息
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedDetail?.title ?? _selectedItem?.title ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: _selectedItem?.source.themeColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      _selectedItem?.source.displayName ?? '',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: _selectedItem?.source.themeColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // 可用内容指示
                                  if (_selectedCover != null)
                                    _buildFeatureChip(Icons.image_rounded, context.l10n.musicManualScraperCoverFeature, isDark),
                                  if (_selectedLyrics?.hasLyrics ?? false) ...[
                                    const SizedBox(width: 4),
                                    _buildFeatureChip(Icons.lyrics_rounded, context.l10n.musicManualScraperLyricsFeature, isDark),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 刮削选项（紧凑）
                    Row(
                      children: [
                        Expanded(
                          child: _buildCompactOption(
                            context.l10n.musicManualScraperCoverOption(_hasCover ? context.l10n.musicManualScraperOverrideLabel : ''),
                            _downloadCover && _selectedCover != null,
                            _selectedCover != null
                                ? (v) => setState(() => _downloadCover = v)
                                : null,
                            theme,
                            isDark,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildCompactOption(
                            context.l10n.musicManualScraperLyricsOption(_hasLyrics ? context.l10n.musicManualScraperOverrideLabel : ''),
                            _downloadLyrics && (_selectedLyrics?.hasLyrics ?? false),
                            (_selectedLyrics?.hasLyrics ?? false)
                                ? (v) => setState(() => _downloadLyrics = v)
                                : null,
                            theme,
                            isDark,
                          ),
                        ),
                        if (_audioFormat != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildCompactOption(
                              context.l10n.musicManualScraperWriteTagsOption,
                              _writeToFile,
                              (v) => setState(() => _writeToFile = v),
                              theme,
                              isDark,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 按钮
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isScraping ? null : () => setState(_clearSelection),
                            child: Text(context.l10n.musicManualScraperDeselectButton),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: _isScraping ? null : _confirmAndScrape,
                            icon: _isScraping
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_rounded, size: 18),
                            label: Text(context.l10n.musicManualScraperConfirmButton),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else
              // 正在加载详情
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      context.l10n.musicManualScraperLoadingDetails,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureChip(IconData icon, String label, bool isDark) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: (isDark ? Colors.green[700] : Colors.green[100])!.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: isDark ? Colors.green[300] : Colors.green[700]),
        const SizedBox(width: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: isDark ? Colors.green[300] : Colors.green[700],
          ),
        ),
      ],
    ),
  );

  Widget _buildCompactOption(
    String label,
    bool value,
    void Function(bool)? onChanged,
    ThemeData theme,
    bool isDark,
  ) {
    final isEnabled = onChanged != null;

    return GestureDetector(
      onTap: isEnabled ? () => onChanged(!value) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: value
              ? AppColors.primary.withValues(alpha: 0.1)
              : (isDark ? Colors.grey[800] : Colors.grey[100]),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: value ? AppColors.primary : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              value ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              size: 16,
              color: isEnabled
                  ? (value ? AppColors.primary : (isDark ? Colors.grey[500] : Colors.grey[600]))
                  : Colors.grey[400],
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: isEnabled
                      ? (isDark ? Colors.white : Colors.black87)
                      : Colors.grey[400],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int ms) {
    final seconds = ms ~/ 1000;
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
