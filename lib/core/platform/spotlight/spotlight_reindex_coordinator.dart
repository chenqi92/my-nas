import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_channel.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_indexer.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_item.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/book_database_service.dart';
import 'package:my_nas/features/comic/data/services/comic_library_cache_service.dart';
import 'package:my_nas/features/music/data/services/music_library_cache_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/shared/services/media_favorites_service.dart';

/// 全量重建协调器：从各模块本地 cache / DB 拉取条目并批量 upsert。
///
/// - video：VideoDatabaseService（已刮削入库的全量条目）
/// - music：MusicLibraryCacheService（NAS 扫描结果缓存）
/// - book ：BookDatabaseService
/// - comic：ComicLibraryCacheService
/// - note ：MediaFavoritesService(type=note)（笔记无中央缓存，
///         只索引已收藏的，避免现扫文件系统）
///
/// 限制单次 upsert 数量上限，避免一次性灌爆 native MethodChannel。
class SpotlightReindexCoordinator {
  SpotlightReindexCoordinator(this._ref);

  final Ref _ref;

  static const int _batchSize = 500;

  /// 是否正在重建（UI 显示 loading）。
  static final progressProvider = StateProvider<bool>((_) => false);

  /// 重建结果摘要：每类 kind -> 条目数。
  static final lastReportProvider =
      StateProvider<Map<SpotlightItemKind, int>?>((_) => null);

  /// 全量重建：先清空 domain，再分类灌入。
  Future<void> rebuildAll() async {
    if (!SpotlightChannel.isSupported) return;

    final indexer = _ref.read(spotlightIndexerProvider);
    _ref.read(progressProvider.notifier).state = true;
    final report = <SpotlightItemKind, int>{};

    try {
      await indexer.clearAll();

      final collectors = <SpotlightItemKind, Future<List<SpotlightItem>>>{
        SpotlightItemKind.video: _collectVideos(),
        SpotlightItemKind.music: _collectMusic(),
        SpotlightItemKind.book: _collectBooks(),
        SpotlightItemKind.comic: _collectComics(),
        SpotlightItemKind.note: _collectNotes(),
      };

      for (final entry in collectors.entries) {
        final items = await entry.value;
        report[entry.key] = items.length;
        for (var i = 0; i < items.length; i += _batchSize) {
          final end =
              (i + _batchSize < items.length) ? i + _batchSize : items.length;
          final batch = items.sublist(i, end);
          await SpotlightChannel.upsertItems(batch);
        }
        logger.i('Spotlight reindex ${entry.key.wireName}: ${items.length}');
      }

      _ref.read(lastReportProvider.notifier).state = report;
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'SpotlightReindexCoordinator.rebuildAll');
    } finally {
      _ref.read(progressProvider.notifier).state = false;
    }
  }

  // ---------------------------------------------------------------------------
  // 各模块条目采集
  // ---------------------------------------------------------------------------

  Future<List<SpotlightItem>> _collectVideos() async {
    try {
      final list = await VideoDatabaseService().getAllVideosQuick();
      return list.map((v) {
        final raw = '${v.sourceId}|${v.filePath}';
        // localPosterUrl 是 file://... 形式；只取本地真实路径
        final thumb = _toLocalPath(v.localPosterUrl);
        return SpotlightItem(
          id: SpotlightIndexer.buildId(SpotlightItemKind.video, raw),
          kind: SpotlightItemKind.video,
          title: (v.title?.isNotEmpty ?? false) ? v.title! : v.fileName,
          subtitle: _buildVideoSubtitle(v),
          thumbPath: thumb,
        );
      }).toList(growable: false);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'collectVideos');
      return const [];
    }
  }

  Future<List<SpotlightItem>> _collectMusic() async {
    try {
      final cache = MusicLibraryCacheService().getCache();
      if (cache == null) return const [];
      return cache.tracks.map((t) {
        final raw = '${t.sourceId}|${t.filePath}';
        return SpotlightItem(
          id: SpotlightIndexer.buildId(SpotlightItemKind.music, raw),
          kind: SpotlightItemKind.music,
          title: t.displayTitle,
          subtitle: '${t.displayArtist} · ${t.displayAlbum}',
        );
      }).toList(growable: false);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'collectMusic');
      return const [];
    }
  }

  Future<List<SpotlightItem>> _collectBooks() async {
    try {
      final list = await BookDatabaseService().getAll();
      return list.map((b) {
        final raw = '${b.sourceId}|${b.filePath}';
        return SpotlightItem(
          id: SpotlightIndexer.buildId(SpotlightItemKind.book, raw),
          kind: SpotlightItemKind.book,
          title: b.displayName,
          subtitle: b.displayAuthor,
          thumbPath: _toLocalPath(b.coverPath),
        );
      }).toList(growable: false);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'collectBooks');
      return const [];
    }
  }

  Future<List<SpotlightItem>> _collectComics() async {
    try {
      final cache = ComicLibraryCacheService().getCache();
      if (cache == null) return const [];
      return cache.comics.map((c) {
        final raw = '${c.sourceId}|${c.folderPath}';
        return SpotlightItem(
          id: SpotlightIndexer.buildId(SpotlightItemKind.comic, raw),
          kind: SpotlightItemKind.comic,
          title: c.folderName,
          subtitle: c.pageCount > 0 ? appL10n.spotlightComicPageCount(c.pageCount) : null,
          thumbPath: _toLocalPath(c.coverPath),
        );
      }).toList(growable: false);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'collectComics');
      return const [];
    }
  }

  Future<List<SpotlightItem>> _collectNotes() async {
    // 笔记没有中央缓存：用 MediaFavorites(type=note) 作为可索引集合。
    // 后续若加了 note DB，可在此切换数据源。
    try {
      final favorites =
          await MediaFavoritesService().getAll(type: MediaType.note);
      return favorites.map((f) {
        final raw = '${f.sourceId}|${f.path}';
        return SpotlightItem(
          id: SpotlightIndexer.buildId(SpotlightItemKind.note, raw),
          kind: SpotlightItemKind.note,
          title: f.displayName,
        );
      }).toList(growable: false);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'collectNotes');
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String? _toLocalPath(String? maybeUrl) {
    if (maybeUrl == null || maybeUrl.isEmpty) return null;
    if (maybeUrl.startsWith('file://')) {
      return Uri.parse(maybeUrl).toFilePath();
    }
    if (maybeUrl.startsWith('/')) return maybeUrl;
    // http(s) URL 不能直接作 Spotlight thumbnail —— 跳过
    return null;
  }

  String? _buildVideoSubtitle(VideoMetadata v) {
    final parts = <String>[];
    if (v.year != null) parts.add(v.year.toString());
    if (v.seasonNumber != null && v.episodeNumber != null) {
      parts.add('S${v.seasonNumber}E${v.episodeNumber}');
    }
    final genres = v.genres;
    if (genres != null && genres.isNotEmpty) {
      parts.add(genres);
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

final spotlightReindexCoordinatorProvider =
    Provider<SpotlightReindexCoordinator>(
  SpotlightReindexCoordinator.new,
);
