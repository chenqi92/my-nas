import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/network/dio_client.dart';
import 'package:my_nas/core/utils/debug_log.dart';
import 'package:my_nas/core/utils/nas_path.dart';
import 'package:my_nas/features/music/data/services/fingerprint/fingerprint_service.dart';
import 'package:my_nas/features/music/data/services/live_activity_service.dart';
import 'package:my_nas/features/music/data/services/music_cover_cache_service.dart';
import 'package:my_nas/features/music/data/services/music_database_service.dart';
import 'package:my_nas/features/music/data/services/music_favorites_service.dart';
import 'package:my_nas/features/music/data/services/music_tag_writer_service.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_result.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/presentation/pages/manual_music_scraper_page.dart';
import 'package:my_nas/features/music/presentation/providers/lyric_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_favorites_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_scraper_provider.dart';
import 'package:my_nas/main.dart' show audioHandler;
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 自动刮削对话框
///
/// 显示刮削进度和结果，允许用户选择下载封面和歌词
class AutoScrapeDialog extends ConsumerStatefulWidget {
  const AutoScrapeDialog({super.key, required this.music, this.fileSystem});

  final MusicItem music;
  final NasFileSystem? fileSystem;

  /// 显示自动刮削对话框
  static Future<bool?> show(
    BuildContext context,
    MusicItem music, {
    NasFileSystem? fileSystem,
  }) => showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        AutoScrapeDialog(music: music, fileSystem: fileSystem),
  );

  @override
  ConsumerState<AutoScrapeDialog> createState() => _AutoScrapeDialogState();
}

class _AutoScrapeDialogState extends ConsumerState<AutoScrapeDialog> {
  // 状态
  _ScrapeStatus _status = _ScrapeStatus.searching;
  String _statusMessage = appL10n.musicAutoScrapeSearching;
  double? _progress;

  // 结果
  MusicScraperDetail? _detail;
  CoverScraperResult? _cover;
  LyricScraperResult? _lyrics;

  // 下载选项
  bool _downloadCover = true;
  bool _downloadLyrics = true;
  bool _writeToFile = true; // 写入到文件标签

  // 错误信息
  String? _errorMessage;

  // 识别方式
  bool _usedFingerprint = false;

  // 标签写入服务
  final _tagWriter = MusicTagWriterService();

  // 文件格式支持信息
  SupportedAudioFormat? _audioFormat;

  /// 检查是否已有封面
  bool get _hasCover =>
      widget.music.coverUrl != null || widget.music.coverData != null;

  /// 检查是否已有歌词
  bool get _hasLyrics =>
      widget.music.lyrics != null && widget.music.lyrics!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // 检查文件格式是否支持写入
    _audioFormat = _tagWriter.getFormat(widget.music.path);
    _startScraping();
  }

  /// 获取本地文件路径
  ///
  /// 如果 url 是 file:// 协议则返回本地路径，否则返回 null
  String? get _localFilePath {
    final url = widget.music.url;
    if (url.startsWith('file://')) {
      return Uri.parse(url).toFilePath();
    }
    // 桌面端可能直接使用本地路径
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      if (File(url).existsSync()) {
        return url;
      }
    }
    return null;
  }

  /// 检查是否可以使用音纹识别
  bool get _canUseFingerprint {
    // 需要本地文件路径且指纹服务可用
    final localPath = _localFilePath;
    if (localPath == null || localPath.isEmpty) return false;
    if (!File(localPath).existsSync()) return false;

    final service = FingerprintService.getInstance();
    return service?.isAvailable ?? false;
  }

  Future<void> _startScraping() async {
    try {
      final manager = ref.read(musicScraperManagerProvider);
      await manager.init();

      // 优先尝试音纹识别（如果可用）
      if (_canUseFingerprint) {
        final fingerprintSuccess = await _tryFingerprintRecognition();
        if (fingerprintSuccess) return;
      }

      // 回退到普通元数据搜索
      await _searchByMetadata();
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '自动刮削失败');
      if (mounted) {
        setState(() {
          _status = _ScrapeStatus.error;
          _statusMessage = context.l10n.musicAutoScrapeFailed;
          _errorMessage = e.toString();
        });
      }
    }
  }

  /// 尝试音纹识别
  Future<bool> _tryFingerprintRecognition() async {
    final localPath = _localFilePath;
    if (localPath == null) return false;

    setState(() {
      _statusMessage = context.l10n.musicAutoScrapeGeneratingFingerprint;
      _progress = 0.1;
    });

    try {
      final service = FingerprintService.getInstance();
      if (service == null) return false;

      // 生成指纹
      final fpData = await service.generateFingerprint(localPath);

      setState(() {
        _statusMessage = context.l10n.musicAutoScrapeIdentifying;
        _progress = 0.4;
      });

      // 查询 AcoustID
      final manager = ref.read(musicScraperManagerProvider);
      final result = await manager.lookupByFingerprint(
        fpData.fingerprint,
        fpData.duration,
      );

      if (result == null || result.isEmpty) {
        // 音纹识别无结果，回退到元数据搜索
        return false;
      }

      setState(() {
        _statusMessage = context.l10n.musicAutoScrapeFetchingDetails;
        _progress = 0.7;
        _usedFingerprint = true;
      });

      // 使用最佳匹配获取详细信息
      final bestMatch = result.bestMatch;
      if (bestMatch != null) {
        final scrapeResult = await manager.scrape(
          title: bestMatch.title ?? widget.music.displayTitle,
          artist: bestMatch.artist,
          album: bestMatch.album,
          getCover: true,
          getLyrics: true,
        );

        _handleScrapeResult(scrapeResult);
        return true;
      }

      return false;
    } on FingerprintException catch (e) {
      // 指纹服务异常，回退到元数据搜索
      debugLog('Fingerprint failed: $e');
      return false;
    }
  }

  /// 通过元数据搜索
  Future<void> _searchByMetadata() async {
    final title = widget.music.displayTitle;
    final artist = widget.music.displayArtist;

    setState(() {
      _statusMessage = context.l10n.musicAutoScrapeSearchTitle(title);
      _progress = 0.2;
    });

    final manager = ref.read(musicScraperManagerProvider);
    final result = await manager.scrape(
      title: title,
      artist: artist.isNotEmpty ? artist : null,
      album: widget.music.album,
      getCover: true,
      getLyrics: true,
    );

    _handleScrapeResult(result);
  }

  /// 处理刮削结果
  void _handleScrapeResult(MusicScrapeResult result) {
    if (!mounted) return;

    if (result.detail == null &&
        result.cover == null &&
        result.lyrics == null) {
      setState(() {
        _status = _ScrapeStatus.notFound;
        _statusMessage = context.l10n.musicAutoScrapeNotFound;
        if (result.errors.isNotEmpty) {
          _errorMessage = result.errors.join('\n');
        }
      });
      return;
    }

    setState(() {
      _status = _ScrapeStatus.found;
      _statusMessage = _usedFingerprint
          ? context.l10n.musicAutoScrapeFingerprintSuccess
          : context.l10n.musicAutoScrapeFoundResults;
      _progress = 1.0;
      _detail = result.detail;
      _cover = result.cover;
      _lyrics = result.lyrics;

      // 如果已有封面，默认不下载（但用户可以勾选覆盖）
      if (_hasCover) {
        _downloadCover = false;
      }

      // 如果已有歌词，默认不下载（但用户可以勾选覆盖）
      if (_hasLyrics) {
        _downloadLyrics = false;
      }
    });
  }

  Future<void> _downloadFiles() async {
    if (widget.fileSystem == null) {
      if (mounted) {
        context.showErrorToast(context.l10n.musicAutoScrapeNoFileSystem);
      }
      return;
    }

    setState(() {
      _status = _ScrapeStatus.downloading;
      _statusMessage = context.l10n.musicAutoScrapeProcessing;
      _progress = 0;
    });

    final fileSystem = widget.fileSystem!;
    final musicPath = widget.music.path;
    // 远端 NAS 路径用 / 分隔；不能用 p.dirname（Windows 宿主上会混入 \）
    final musicDir = nasPathDirname(musicPath);
    final baseName = nasPathBasenameWithoutExtension(musicPath);

    var completedSteps = 0;
    final totalSteps =
        (_downloadCover && _cover != null ? 1 : 0) +
        (_downloadLyrics && _lyrics != null ? 1 : 0) +
        (_writeToFile && _audioFormat != null ? 1 : 0);

    // 下载封面数据（用于写入标签和保存文件）
    Uint8List? coverData;
    String? coverMimeType;

    try {
      // 下载封面
      if (_downloadCover && _cover != null) {
        setState(() {
          _statusMessage = context.l10n.musicAutoScrapeDownloadingCover;
        });

        final result = await _downloadCoverData();
        coverData = result.$1;
        coverMimeType = result.$2;

        await _saveCoverFile(fileSystem, musicDir, baseName, coverData);

        // 同步封面到本地缓存和数据库
        if (coverData != null) {
          await _syncCoverToLocalCache(coverData);
        }

        completedSteps++;
        setState(() {
          _progress = completedSteps / totalSteps;
        });
      }

      // 下载歌词
      if (_downloadLyrics && _lyrics != null) {
        setState(() {
          _statusMessage = context.l10n.musicAutoScrapeDownloadingLyrics;
        });

        await _downloadLyrics_(fileSystem, musicDir, baseName);
        completedSteps++;
        setState(() {
          _progress = completedSteps / totalSteps;
        });

        // 如果当前正在播放这首歌，通知歌词 provider 重新加载
        final currentMusic = ref.read(currentMusicProvider);
        if (currentMusic?.id == widget.music.id) {
          AppError.fireAndForget(
            ref.read(currentLyricProvider.notifier).loadLyrics(widget.music),
            action: 'reloadLyricsAfterScrape',
          );
        }
      }

      // 写入到文件标签
      if (_writeToFile && _audioFormat != null) {
        setState(() {
          _statusMessage = context.l10n.musicAutoScrapeWritingTags(
            _audioFormat!.tagType,
          );
        });

        await _writeTagsToFile(fileSystem, musicPath, coverData, coverMimeType);
        completedSteps++;
        setState(() {
          _progress = completedSteps / totalSteps;
        });
      }

      // 无论是否下载封面，都保存元数据到数据库
      // 这确保年代、艺术家、专辑、流派等信息被正确保存
      if (_detail != null) {
        await _syncMetadataToDatabase(coverData);
      }

      setState(() {
        _status = _ScrapeStatus.completed;
        _statusMessage = context.l10n.musicAutoScrapeCompleted;
        _progress = 1.0;
      });

      // 延迟关闭
      await Future<void>.delayed(const Duration(seconds: 1));
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '处理文件失败');
      setState(() {
        _status = _ScrapeStatus.error;
        _statusMessage = context.l10n.musicAutoScrapeProcessingFailed;
        _errorMessage = e.toString();
      });
    }
  }

  /// 下载封面数据
  Future<(Uint8List?, String?)> _downloadCoverData() async {
    if (_cover == null) return (null, null);

    try {
      final dio = DioClient.createTlsAware();
      final response = await dio.get<List<int>>(
        _cover!.coverUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.data == null) return (null, null);

      final coverData = Uint8List.fromList(response.data!);
      final mimeType = _cover!.coverUrl.contains('.png')
          ? 'image/png'
          : 'image/jpeg';

      return (coverData, mimeType);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '下载封面数据失败');
      return (null, null);
    }
  }

  /// 保存封面文件到目录
  Future<void> _saveCoverFile(
    NasFileSystem fileSystem,
    String musicDir,
    String baseName,
    Uint8List? coverData,
  ) async {
    if (coverData == null) return;

    try {
      final ext = _cover!.coverUrl.contains('.png') ? 'png' : 'jpg';

      // 尝试保存为 folder.jpg，如果已存在则保存为 {filename}-cover.jpg
      final folderCoverPath = nasPathJoin(musicDir, 'folder.$ext');
      var exists = false;
      try {
        await fileSystem.getFileInfo(folderCoverPath);
        exists = true;
      } on Exception {
        exists = false;
      }

      final coverPath = exists
          ? nasPathJoin(musicDir, '$baseName-cover.$ext')
          : folderCoverPath;

      await fileSystem.writeFile(coverPath, coverData);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '保存封面文件失败');
    }
  }

  /// 同步封面到本地磁盘缓存和数据库
  /// 确保刮削后的封面能够被正确显示，无需重新提取
  Future<void> _syncCoverToLocalCache(Uint8List coverData) async {
    final sourceId = widget.music.sourceId;
    if (sourceId == null) return;

    try {
      // 1. 保存封面到本地磁盘缓存
      final coverCache = MusicCoverCacheService();
      await coverCache.init();

      final uniqueKey = '${sourceId}_${widget.music.path}';
      final localCoverPath = await coverCache.saveCover(uniqueKey, coverData);

      if (localCoverPath == null) return;

      // 2. 更新数据库中的封面路径
      final db = MusicDatabaseService();
      await db.init();

      // 获取现有的曲目数据并更新
      final existing = await db.get(sourceId, widget.music.path);
      if (existing != null) {
        // 补充缺失的元数据字段（不覆盖已有数据）
        await db.upsert(
          existing.copyWith(
            coverPath: localCoverPath,
            // 只在缺失时补充
            title: (existing.title == null || existing.title!.isEmpty)
                ? _detail?.title
                : existing.title,
            artist: (existing.artist == null || existing.artist!.isEmpty)
                ? _detail?.artist
                : existing.artist,
            album: (existing.album == null || existing.album!.isEmpty)
                ? _detail?.album
                : existing.album,
            year: existing.year ?? _detail?.year,
            trackNumber: existing.trackNumber ?? _detail?.trackNumber,
            genre: (existing.genre == null || existing.genre!.isEmpty)
                ? _detail?.genres?.join(', ')
                : existing.genre,
            lastUpdated: DateTime.now(),
          ),
        );
      } else {
        // 如果数据库中没有这首歌，创建一个基本条目
        await db.upsert(
          MusicTrackEntity(
            sourceId: sourceId,
            filePath: widget.music.path,
            fileName: widget.music.name,
            title: _detail?.title ?? widget.music.title,
            artist: _detail?.artist ?? widget.music.artist,
            album: _detail?.album ?? widget.music.album,
            year: _detail?.year,
            trackNumber: _detail?.trackNumber,
            genre: _detail?.genres?.join(', '),
            coverPath: localCoverPath,
            duration: widget.music.duration?.inMilliseconds,
            lastUpdated: DateTime.now(),
          ),
        );
      }

      // 3. 更新当前播放状态（如果正在播放这首歌）
      final currentMusic = ref.read(currentMusicProvider);
      final isCurrentlyPlaying = currentMusic?.id == widget.music.id;

      if (isCurrentlyPlaying) {
        final updatedMusic = currentMusic!.copyWith(
          coverData: coverData.toList(),
          coverUrl: 'file://$localCoverPath',
          // 补充缺失的元数据
          title: (currentMusic.title == null || currentMusic.title!.isEmpty)
              ? _detail?.title
              : currentMusic.title,
          artist: (currentMusic.artist == null || currentMusic.artist!.isEmpty)
              ? _detail?.artist
              : currentMusic.artist,
          album: (currentMusic.album == null || currentMusic.album!.isEmpty)
              ? _detail?.album
              : currentMusic.album,
          year: currentMusic.year ?? _detail?.year,
          trackNumber: currentMusic.trackNumber ?? _detail?.trackNumber,
          genre: (currentMusic.genre == null || currentMusic.genre!.isEmpty)
              ? _detail?.genres?.join(', ')
              : currentMusic.genre,
        );
        ref.read(currentMusicProvider.notifier).state = updatedMusic;

        // 4. 更新 Now Playing / 锁屏控制中心的封面
        await audioHandler.updateArtwork(coverData);

        // 5. 更新灵动岛的封面（仅 iOS）
        if (Platform.isIOS) {
          await LiveActivityService().updateCoverImage(updatedMusic, coverData);
        }
      }

      // 6. 更新播放队列中该歌曲的封面（确保队列列表显示正确）
      ref
          .read(playQueueProvider.notifier)
          .updateTrackCover(
            widget.music.id,
            coverData: coverData.toList(),
            coverUrl: 'file://$localCoverPath',
          );

      // 7. 更新收藏和播放历史中的封面
      final newCoverUrl = 'file://$localCoverPath';
      await MusicFavoritesService().updateCoverUrl(
        widget.music.path,
        newCoverUrl,
      );

      // 8. 刷新收藏和播放历史的 provider（使 UI 立即更新）
      AppError.fireAndForget(
        ref.read(musicFavoritesProvider.notifier).refresh(),
        action: 'autoScrape.refreshFavorites',
      );
      AppError.fireAndForget(
        ref.read(musicHistoryProvider.notifier).refresh(),
        action: 'autoScrape.refreshHistory',
      );
    } on Exception catch (e, st) {
      // 非关键功能，静默失败
      AppError.ignore(e, st, '同步封面到本地缓存失败');
    }
  }

  /// 同步元数据到数据库（不包含封面）
  /// 当用户没有下载封面时，仍需要保存刮削到的元数据
  Future<void> _syncMetadataToDatabase(Uint8List? coverData) async {
    final sourceId = widget.music.sourceId;
    if (sourceId == null || _detail == null) return;

    try {
      final db = MusicDatabaseService();
      await db.init();

      // 获取现有的曲目数据并更新
      final existing = await db.get(sourceId, widget.music.path);
      if (existing != null) {
        // 补充缺失的元数据字段（不覆盖已有数据）
        final updated = existing.copyWith(
          title: (existing.title == null || existing.title!.isEmpty)
              ? _detail?.title
              : existing.title,
          artist: (existing.artist == null || existing.artist!.isEmpty)
              ? _detail?.artist
              : existing.artist,
          album: (existing.album == null || existing.album!.isEmpty)
              ? _detail?.album
              : existing.album,
          year: existing.year ?? _detail?.year,
          trackNumber: existing.trackNumber ?? _detail?.trackNumber,
          genre: (existing.genre == null || existing.genre!.isEmpty)
              ? _detail?.genres?.join(', ')
              : existing.genre,
          lastUpdated: DateTime.now(),
        );
        await db.upsert(updated);
      } else {
        // 如果数据库中没有这首歌，创建一个基本条目
        await db.upsert(
          MusicTrackEntity(
            sourceId: sourceId,
            filePath: widget.music.path,
            fileName: widget.music.name,
            title: _detail?.title ?? widget.music.title,
            artist: _detail?.artist ?? widget.music.artist,
            album: _detail?.album ?? widget.music.album,
            year: _detail?.year,
            trackNumber: _detail?.trackNumber,
            genre: _detail?.genres?.join(', '),
            duration: widget.music.duration?.inMilliseconds,
            lastUpdated: DateTime.now(),
          ),
        );
      }

      // 更新当前播放状态中的元数据（如果正在播放这首歌）
      final currentMusic = ref.read(currentMusicProvider);
      final isCurrentlyPlaying = currentMusic?.id == widget.music.id;

      if (isCurrentlyPlaying) {
        final updatedMusic = currentMusic!.copyWith(
          // 如果有封面数据，也一并更新
          coverData: coverData?.toList() ?? currentMusic.coverData,
          // 补充缺失的元数据
          title: (currentMusic.title == null || currentMusic.title!.isEmpty)
              ? _detail?.title
              : currentMusic.title,
          artist: (currentMusic.artist == null || currentMusic.artist!.isEmpty)
              ? _detail?.artist
              : currentMusic.artist,
          album: (currentMusic.album == null || currentMusic.album!.isEmpty)
              ? _detail?.album
              : currentMusic.album,
          year: currentMusic.year ?? _detail?.year,
          trackNumber: currentMusic.trackNumber ?? _detail?.trackNumber,
          genre: (currentMusic.genre == null || currentMusic.genre!.isEmpty)
              ? _detail?.genres?.join(', ')
              : currentMusic.genre,
        );
        ref.read(currentMusicProvider.notifier).state = updatedMusic;
      }

      // 更新播放队列中该歌曲的元数据
      ref
          .read(playQueueProvider.notifier)
          .updateTrackMetadata(
            widget.music.id,
            title: _detail?.title,
            artist: _detail?.artist,
            album: _detail?.album,
            year: _detail?.year,
            trackNumber: _detail?.trackNumber,
            genre: _detail?.genres?.join(', '),
          );
    } on Exception catch (e, st) {
      // 非关键功能，静默失败
      AppError.ignore(e, st, '同步元数据到数据库失败');
    }
  }

  /// 写入标签到音频文件
  Future<void> _writeTagsToFile(
    NasFileSystem fileSystem,
    String musicPath,
    Uint8List? coverData,
    String? coverMimeType,
  ) async {
    try {
      await _tagWriter.init();

      // 构建要写入的标签数据
      final tagData = MusicTagData(
        title: _detail?.title,
        artist: _detail?.artist,
        album: _detail?.album,
        albumArtist: _detail?.albumArtist,
        year: _detail?.year,
        trackNumber: _detail?.trackNumber,
        discNumber: _detail?.discNumber,
        genre: _detail?.genres?.join(', '),
        lyrics: _lyrics?.lrcContent ?? _lyrics?.plainText,
        coverData: coverData,
        coverMimeType: coverMimeType,
      );

      final result = await _tagWriter.writeToNasFile(
        fileSystem,
        musicPath,
        tagData,
        sourceId: widget.music.sourceId,
      );

      if (!result.success) {
        throw Exception(result.error);
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '写入标签失败');
      rethrow;
    }
  }

  /// 打开手动刮削页面
  void _openManualScraper() {
    Navigator.of(context).pop(false); // 先关闭当前对话框
    Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (context) => ManualMusicScraperPage(
          music: widget.music,
          fileSystem: widget.fileSystem,
        ),
      ),
    );
  }

  Future<void> _downloadLyrics_(
    NasFileSystem fileSystem,
    String musicDir,
    String baseName,
  ) async {
    if (_lyrics == null || !_lyrics!.hasLyrics) return;

    try {
      final lrcContent = _lyrics!.lrcContent ?? _lyrics!.plainText ?? '';
      if (lrcContent.isEmpty) return;

      final lrcPath = nasPathJoin(musicDir, '$baseName.lrc');
      // 使用 UTF-8 编码保存歌词文件
      final utf8Bytes = const Utf8Encoder().convert(lrcContent);
      await fileSystem.writeFile(lrcPath, Uint8List.fromList(utf8Bytes));
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '下载歌词失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      title: Row(
        children: [
          Icon(Icons.auto_fix_high_rounded, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(context.l10n.musicAutoScrapeTitle)),
          // 手动搜索按钮放在右上角
          TextButton.icon(
            onPressed: _openManualScraper,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: Text(context.l10n.musicAutoScrapeManualButton),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 当前音乐信息
            _buildMusicInfo(theme, isDark),
            const SizedBox(height: 16),

            // 状态/进度
            _buildStatus(theme, isDark),

            // 结果预览
            if (_status == _ScrapeStatus.found) ...[
              const SizedBox(height: 16),
              _buildResults(theme, isDark),
            ],

            // 错误信息
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(fontSize: 12, color: AppColors.error),
                ),
              ),
            ],
          ],
        ),
      ),
      // 将按钮包裹在 OverflowBar 中以自动处理溢出
      actionsOverflowButtonSpacing: 8,
      actionsAlignment: MainAxisAlignment.end,
      actions: _buildActions(isDark),
    );
  }

  Widget _buildMusicInfo(ThemeData theme, bool isDark) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: isDark
          ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
          : Colors.grey[100],
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        // 封面
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: AppColors.primary.withValues(alpha: 0.1),
          ),
          clipBehavior: Clip.antiAlias,
          child: _buildCoverImage(),
        ),
        const SizedBox(width: 12),

        // 信息
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.music.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                widget.music.displayArtist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppColors.darkOnSurfaceVariant
                      : AppColors.lightOnSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildCoverImage() {
    // 如果有 coverData，优先使用
    if (widget.music.coverData != null) {
      return Image.memory(
        Uint8List.fromList(widget.music.coverData!),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            Icon(Icons.music_note_rounded, color: AppColors.primary),
      );
    }

    // 如果有 coverUrl
    if (widget.music.coverUrl != null) {
      return Image.network(
        widget.music.coverUrl!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            Icon(Icons.music_note_rounded, color: AppColors.primary),
      );
    }

    // 默认图标
    return Icon(Icons.music_note_rounded, color: AppColors.primary);
  }

  Widget _buildStatus(ThemeData theme, bool isDark) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // 状态文字
      Row(
        children: [
          if (_status == _ScrapeStatus.searching ||
              _status == _ScrapeStatus.downloading)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            )
          else if (_status == _ScrapeStatus.found ||
              _status == _ScrapeStatus.completed)
            Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success)
          else if (_status == _ScrapeStatus.notFound)
            Icon(Icons.search_off_rounded, size: 16, color: AppColors.warning)
          else if (_status == _ScrapeStatus.error)
            Icon(Icons.error_rounded, size: 16, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _statusMessage,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
          ),
        ],
      ),

      // 进度条
      if (_progress != null &&
          (_status == _ScrapeStatus.searching ||
              _status == _ScrapeStatus.downloading)) ...[
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: _progress,
          backgroundColor: isDark
              ? AppColors.darkSurfaceVariant
              : AppColors.lightSurfaceVariant,
          color: AppColors.primary,
        ),
      ],
    ],
  );

  Widget _buildResults(ThemeData theme, bool isDark) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        context.l10n.musicAutoScrapeFoundContent,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.grey[300] : Colors.grey[700],
        ),
      ),
      const SizedBox(height: 8),

      // 元数据
      if (_detail != null)
        _buildResultRow(
          isDark,
          Icons.info_outline_rounded,
          context.l10n.musicAutoScrapeMetadata,
          '${_detail!.title} - ${_detail!.artist ?? context.l10n.musicAutoScrapeArtistUnknown}',
          source: _detail!.source,
          // 显示来源是否支持歌词
          badge: _detail!.source.supportsLyrics
              ? Icon(
                  Icons.lyrics_rounded,
                  size: 12,
                  color: isDark ? Colors.cyan[300] : Colors.cyan[700],
                )
              : null,
        ),

      // 封面
      if (_cover != null)
        _buildResultRow(
          isDark,
          Icons.image_rounded,
          _hasCover
              ? context.l10n.musicAutoScrapeCoverExisting
              : context.l10n.musicAutoScrapeCover,
          _hasCover && _downloadCover
              ? context.l10n.musicAutoScrapeCoverOverwrite
              : context.l10n.musicAutoScrapeCoverFrom(
                  _cover!.source.displayName,
                ),
          source: _cover!.source,
          trailing: Checkbox(
            value: _downloadCover,
            onChanged: (v) => setState(() => _downloadCover = v ?? true),
            visualDensity: VisualDensity.compact,
          ),
        ),

      // 歌词
      if (_lyrics != null && _lyrics!.hasLyrics)
        _buildResultRow(
          isDark,
          Icons.lyrics_rounded,
          _hasLyrics
              ? context.l10n.musicAutoScrapeLyricsExisting
              : context.l10n.musicAutoScrapeLyrics,
          _hasLyrics && _downloadLyrics
              ? context.l10n.musicAutoScrapeLyricsOverwrite
              : _lyrics!.isLrc
              ? context.l10n.musicAutoScrapeLyricsLrc
              : context.l10n.musicAutoScrapeLyricsPlainText,
          source: _lyrics!.source,
          trailing: Checkbox(
            value: _downloadLyrics,
            onChanged: (v) => setState(() => _downloadLyrics = v ?? true),
            visualDensity: VisualDensity.compact,
          ),
        ),

      // 写入到文件标签选项
      if (_audioFormat != null) ...[
        const SizedBox(height: 8),
        const Divider(height: 1),
        const SizedBox(height: 8),
        _buildResultRow(
          isDark,
          Icons.edit_note_rounded,
          context.l10n.musicAutoScrapeWriteTags,
          '${_audioFormat!.displayName} (${_audioFormat!.tagType})',
          trailing: Checkbox(
            value: _writeToFile,
            onChanged: (v) => setState(() => _writeToFile = v ?? true),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],

      // 不支持写入标签时提示
      if (_audioFormat == null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 14,
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  context.l10n.musicAutoScrapeFormatNotSupported,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                ),
              ),
            ],
          ),
        ),

      // 无封面/歌词时提示
      if (_cover == null && _lyrics == null && _detail != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            context.l10n.musicAutoScrapeNoCoverAndLyrics,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[500] : Colors.grey[600],
            ),
          ),
        ),
    ],
  );

  Widget _buildResultRow(
    bool isDark,
    IconData icon,
    String label,
    String value, {
    MusicScraperType? source,
    Widget? trailing,
    Widget? badge,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: isDark
              ? AppColors.darkOnSurfaceVariant
              : AppColors.lightOnSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                    ),
                  ),
                  if (badge != null) ...[const SizedBox(width: 4), badge],
                ],
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );

  List<Widget> _buildActions(bool isDark) {
    switch (_status) {
      case _ScrapeStatus.searching:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.musicAutoScrapeCancel),
          ),
        ];

      case _ScrapeStatus.found:
        final hasDownloadable =
            (_downloadCover && _cover != null) ||
            (_downloadLyrics && _lyrics != null);
        final hasWritable =
            _writeToFile && _audioFormat != null && _detail != null;
        final hasAction = hasDownloadable || hasWritable;
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.musicAutoScrapeCancel),
          ),
          if (hasAction && widget.fileSystem != null)
            FilledButton(
              onPressed: _downloadFiles,
              child: Text(
                hasWritable
                    ? context.l10n.musicAutoScrapeApply
                    : context.l10n.musicAutoScrapeDownload,
              ),
            ),
        ];

      case _ScrapeStatus.downloading:
        return [];

      case _ScrapeStatus.completed:
        return [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.musicAutoScrapeDone),
          ),
        ];

      case _ScrapeStatus.notFound:
      case _ScrapeStatus.error:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.musicAutoScrapeClose),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                _status = _ScrapeStatus.searching;
                _statusMessage = context.l10n.musicAutoScrapeSearching;
                _progress = null;
                _errorMessage = null;
              });
              _startScraping();
            },
            child: Text(context.l10n.musicAutoScrapeRetry),
          ),
        ];
    }
  }
}

enum _ScrapeStatus { searching, found, downloading, completed, notFound, error }
