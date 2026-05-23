import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/media_server_adapters/base/media_server_entities.dart';

/// 元数据来源
enum MetadataSource {
  /// 媒体服务器元数据（最高优先级）
  server('server', '媒体服务器'),

  /// NFO 文件（本地元数据）
  nfo('nfo', 'NFO'),

  /// TMDB 刮削
  tmdb('tmdb', 'TMDB'),

  /// 豆瓣刮削
  douban('douban', '豆瓣'),

  /// 文件名解析（最低优先级）
  filename('filename', '文件名');

  const MetadataSource(this.id, this.displayName);

  final String id;
  final String displayName;

  /// 优先级（数字越小优先级越高）
  int get priority => switch (this) {
        server => 0,
        nfo => 1,
        tmdb => 2,
        douban => 3,
        filename => 99,
      };

  static MetadataSource fromId(String? id) => switch (id) {
        'server' => server,
        'nfo' => nfo,
        'tmdb' => tmdb,
        'douban' => douban,
        'filename' => filename,
        _ => filename,
      };
}

/// 元数据优先级服务
///
/// 实现元数据来源优先级：服务器 > NFO > TMDB > 豆瓣 > 文件名
class MetadataPriorityService {
  const MetadataPriorityService();

  /// 合并元数据，根据优先级决定使用哪个来源的数据
  ///
  /// [existing] 现有元数据
  /// [newData] 新元数据
  /// [newSource] 新元数据来源
  /// [forceOverwrite] 强制覆盖（忽略优先级）
  ///
  /// 返回合并后的元数据
  VideoMetadata mergeMetadata(
    VideoMetadata existing,
    VideoMetadata newData,
    MetadataSource newSource, {
    bool forceOverwrite = false,
  }) {
    final existingSource = MetadataSource.fromId(existing.scrapeSource);

    // 如果强制覆盖或新来源优先级更高（数字更小）
    if (forceOverwrite || newSource.priority < existingSource.priority) {
      return _mergeWithPriority(existing, newData, newSource);
    }

    // 新来源优先级较低，只补充缺失字段
    return _mergeSupplemental(existing, newData, existingSource);
  }

  /// 优先级合并：新数据覆盖旧数据
  VideoMetadata _mergeWithPriority(
    VideoMetadata existing,
    VideoMetadata newData,
    MetadataSource source,
  ) => existing.copyWith(
      // 基础信息
      title: newData.title ?? existing.title,
      originalTitle: newData.originalTitle ?? existing.originalTitle,
      year: newData.year ?? existing.year,
      overview: newData.overview ?? existing.overview,
      category: newData.category != MediaCategory.unknown
          ? newData.category
          : existing.category,

      // 图片
      posterUrl: newData.posterUrl ?? existing.posterUrl,
      backdropUrl: newData.backdropUrl ?? existing.backdropUrl,

      // 评分
      rating: newData.rating ?? existing.rating,
      imdbRating: newData.imdbRating ?? existing.imdbRating,

      // 详细信息
      runtime: newData.runtime ?? existing.runtime,
      genres: newData.genres ?? existing.genres,
      countries: newData.countries ?? existing.countries,
      director: newData.director ?? existing.director,
      cast: newData.cast ?? existing.cast,
      certification: newData.certification ?? existing.certification,

      // 外部 ID
      tmdbId: newData.tmdbId ?? existing.tmdbId,
      imdbId: newData.imdbId ?? existing.imdbId,
      doubanId: newData.doubanId ?? existing.doubanId,

      // 剧集信息
      seasonNumber: newData.seasonNumber ?? existing.seasonNumber,
      episodeNumber: newData.episodeNumber ?? existing.episodeNumber,
      episodeTitle: newData.episodeTitle ?? existing.episodeTitle,

      // 电影系列
      collectionId: newData.collectionId ?? existing.collectionId,
      collectionName: newData.collectionName ?? existing.collectionName,
      collectionPosterUrl:
          newData.collectionPosterUrl ?? existing.collectionPosterUrl,
      collectionBackdropUrl:
          newData.collectionBackdropUrl ?? existing.collectionBackdropUrl,

      // 多语言
      localizedTitles: _mergeLocalizedMap(
        existing.localizedTitles,
        newData.localizedTitles,
      ),
      localizedOverviews: _mergeLocalizedMap(
        existing.localizedOverviews,
        newData.localizedOverviews,
      ),

      // 媒体服务器相关
      serverType: newData.serverType ?? existing.serverType,
      serverItemId: newData.serverItemId ?? existing.serverItemId,

      // 标记来源和更新时间
      scrapeSource: source.id,
      scrapeStatus: ScrapeStatus.completed,
      lastUpdated: DateTime.now(),
    );

  /// 补充合并：只填充缺失字段
  VideoMetadata _mergeSupplemental(
    VideoMetadata existing,
    VideoMetadata newData,
    MetadataSource existingSource,
  ) => existing.copyWith(
      // 只补充空缺字段
      title: existing.title ?? newData.title,
      originalTitle: existing.originalTitle ?? newData.originalTitle,
      year: existing.year ?? newData.year,
      overview: existing.overview ?? newData.overview,
      posterUrl: existing.posterUrl ?? newData.posterUrl,
      backdropUrl: existing.backdropUrl ?? newData.backdropUrl,
      rating: existing.rating ?? newData.rating,
      imdbRating: existing.imdbRating ?? newData.imdbRating,
      runtime: existing.runtime ?? newData.runtime,
      genres: existing.genres ?? newData.genres,
      countries: existing.countries ?? newData.countries,
      director: existing.director ?? newData.director,
      cast: existing.cast ?? newData.cast,
      certification: existing.certification ?? newData.certification,
      tmdbId: existing.tmdbId ?? newData.tmdbId,
      imdbId: existing.imdbId ?? newData.imdbId,
      doubanId: existing.doubanId ?? newData.doubanId,
      collectionId: existing.collectionId ?? newData.collectionId,
      collectionName: existing.collectionName ?? newData.collectionName,

      // 合并多语言数据（两个来源都保留）
      localizedTitles: _mergeLocalizedMap(
        existing.localizedTitles,
        newData.localizedTitles,
      ),
      localizedOverviews: _mergeLocalizedMap(
        existing.localizedOverviews,
        newData.localizedOverviews,
      ),

      // 保持原有来源标记
      scrapeSource: existingSource.id,
      lastUpdated: DateTime.now(),
    );

  /// 合并多语言 Map
  Map<String, String>? _mergeLocalizedMap(
    Map<String, String>? existing,
    Map<String, String>? newData,
  ) {
    if (existing == null && newData == null) return null;
    if (existing == null) return newData;
    if (newData == null) return existing;

    return {...existing, ...newData};
  }

  /// 从 MediaItem 创建 VideoMetadata
  ///
  /// 用于将媒体服务器的元数据转换为本地格式
  VideoMetadata fromMediaItem({
    required MediaItem item,
    required String filePath,
    required String sourceId,
    required String fileName,
    String? serverType,
  }) => VideoMetadata(
      filePath: filePath,
      sourceId: sourceId,
      fileName: fileName,
      category: _getCategory(item.type),
      scrapeStatus: ScrapeStatus.completed,
      scrapeSource: MetadataSource.server.id,
      title: item.name,
      year: item.productionYear,
      overview: item.overview,
      rating: item.communityRating,
      runtime: item.runTimeTicks != null
          ? (item.runTimeTicks! ~/ (10000000 * 60))
          : null,
      genres: item.genres?.join(' / '),
      seasonNumber: item.parentIndexNumber,
      episodeNumber: item.indexNumber,
      episodeTitle: item.type == MediaItemType.episode ? item.name : null,
      tmdbId: item.tmdbId != null ? int.tryParse(item.tmdbId!) : null,
      imdbId: item.imdbId,
      serverType: serverType,
      serverItemId: item.id,
      lastUpdated: DateTime.now(),
      // 用户数据
      isWatched: item.userData?.played ?? false,
      playbackPositionTicks: item.userData?.playbackPositionTicks,
      lastPlayedAt: item.userData?.lastPlayedDate,
    );

  /// 从 MediaItem 更新现有元数据
  ///
  /// 服务器元数据优先级最高，会覆盖其他来源的数据
  VideoMetadata updateFromMediaItem(
    VideoMetadata existing,
    MediaItem item, {
    String? serverType,
  }) {
    final serverMetadata = VideoMetadata(
      filePath: existing.filePath,
      sourceId: existing.sourceId,
      fileName: existing.fileName,
      category: _getCategory(item.type),
      title: item.name,
      year: item.productionYear,
      overview: item.overview,
      rating: item.communityRating,
      runtime: item.runTimeTicks != null
          ? (item.runTimeTicks! ~/ (10000000 * 60))
          : null,
      genres: item.genres?.join(' / '),
      seasonNumber: item.parentIndexNumber,
      episodeNumber: item.indexNumber,
      episodeTitle: item.type == MediaItemType.episode ? item.name : null,
      tmdbId: item.tmdbId != null ? int.tryParse(item.tmdbId!) : null,
      imdbId: item.imdbId,
      serverType: serverType,
      serverItemId: item.id,
      isWatched: item.userData?.played ?? false,
      playbackPositionTicks: item.userData?.playbackPositionTicks,
      lastPlayedAt: item.userData?.lastPlayedDate,
    );

    return mergeMetadata(existing, serverMetadata, MetadataSource.server);
  }

  MediaCategory _getCategory(MediaItemType type) => switch (type) {
        MediaItemType.movie => MediaCategory.movie,
        MediaItemType.series ||
        MediaItemType.season ||
        MediaItemType.episode =>
          MediaCategory.tvShow,
        _ => MediaCategory.unknown,
      };

  /// 判断元数据是否需要更新
  ///
  /// [existing] 现有元数据
  /// [newSource] 新数据来源
  /// [maxAge] 最大缓存时间
  bool shouldUpdate(
    VideoMetadata existing,
    MetadataSource newSource, {
    Duration maxAge = const Duration(days: 7),
  }) {
    final existingSource = MetadataSource.fromId(existing.scrapeSource);

    // 优先级更高的来源总是应该更新
    if (newSource.priority < existingSource.priority) {
      return true;
    }

    // 相同来源，检查是否过期
    if (newSource == existingSource && existing.lastUpdated != null) {
      final age = DateTime.now().difference(existing.lastUpdated!);
      return age > maxAge;
    }

    // 没有元数据，需要更新
    if (!existing.hasMetadata) {
      return true;
    }

    return false;
  }
}

/// 元数据优先级服务 Provider
final metadataPriorityServiceProvider = Provider<MetadataPriorityService>(
  (ref) => const MetadataPriorityService(),
);
