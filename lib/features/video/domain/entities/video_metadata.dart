import 'dart:convert';

import 'package:my_nas/features/video/data/services/tmdb_service.dart';

/// 媒体类型
enum MediaCategory {
  movie,
  tvShow,
  unknown,
}

/// 刮削状态
enum ScrapeStatus {
  /// 未刮削（新扫描到的文件）
  pending,

  /// 刮削中
  scraping,

  /// 已刮削成功（成功获取TMDB数据）
  completed,

  /// 刮削失败（无匹配或API错误）
  failed,

  /// 已跳过（用户手动标记或不需要刮削）
  skipped,
}

/// 视频元数据
class VideoMetadata {
  VideoMetadata({
    required this.filePath,
    required this.sourceId,
    required this.fileName,
    this.category = MediaCategory.unknown,
    this.scrapeStatus = ScrapeStatus.pending,
    this.tmdbId,
    this.doubanId,
    this.title,
    this.originalTitle,
    this.year,
    this.overview,
    this.posterUrl,
    this.backdropUrl,
    this.rating,
    this.runtime,
    this.genres,
    this.countries,
    this.director,
    this.cast,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeTitle,
    this.lastUpdated,
    this.thumbnailUrl,
    this.generatedThumbnailUrl,
    this.localPosterUrl,
    this.fileSize,
    this.fileModifiedTime,
    this.collectionId,
    this.collectionName,
    this.collectionPosterUrl,
    this.collectionBackdropUrl,
    this.showDirectory,
    this.movieDirectory,
    this.resolution,
    this.localizedTitles,
    this.localizedOverviews,
    // 扩展视频信息
    this.videoSource,
    this.videoCodec,
    this.hdrFormat,
    this.audioFormat,
    this.is3D = false,
    this.isRemux = false,
    // 扩展评分
    this.imdbId,
    this.imdbRating,
    this.metacriticRating,
    this.traktRating,
    // 内容分级
    this.certification,
    // 媒体服务器相关
    this.serverType,
    this.serverItemId,
    this.scrapeSource,
    this.isWatched = false,
    this.playbackPositionTicks,
    this.lastPlayedAt,
  });

  /// 从 Map 创建
  factory VideoMetadata.fromMap(Map<dynamic, dynamic> map) => VideoMetadata(
      filePath: map['filePath'] as String,
      sourceId: map['sourceId'] as String,
      fileName: map['fileName'] as String,
      category: MediaCategory.values[map['category'] as int? ?? 2],
      scrapeStatus: ScrapeStatus.values[map['scrapeStatus'] as int? ?? 0],
      tmdbId: map['tmdbId'] as int?,
      doubanId: map['doubanId'] as String?,
      title: map['title'] as String?,
      originalTitle: map['originalTitle'] as String?,
      year: map['year'] as int?,
      overview: map['overview'] as String?,
      posterUrl: map['posterUrl'] as String?,
      backdropUrl: map['backdropUrl'] as String?,
      rating: (map['rating'] as num?)?.toDouble(),
      runtime: map['runtime'] as int?,
      genres: map['genres'] as String?,
      countries: map['countries'] as String?,
      director: map['director'] as String?,
      cast: map['cast'] as String?,
      seasonNumber: map['seasonNumber'] as int?,
      episodeNumber: map['episodeNumber'] as int?,
      episodeTitle: map['episodeTitle'] as String?,
      lastUpdated: map['lastUpdated'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastUpdated'] as int)
          : null,
      thumbnailUrl: map['thumbnailUrl'] as String?,
      generatedThumbnailUrl: map['generatedThumbnailUrl'] as String?,
      localPosterUrl: map['localPosterUrl'] as String?,
      fileSize: map['fileSize'] as int?,
      fileModifiedTime: map['fileModifiedTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['fileModifiedTime'] as int)
          : null,
      collectionId: map['collectionId'] as int?,
      collectionName: map['collectionName'] as String?,
      collectionPosterUrl: map['collectionPosterUrl'] as String?,
      collectionBackdropUrl: map['collectionBackdropUrl'] as String?,
      showDirectory: map['showDirectory'] as String?,
      movieDirectory: map['movieDirectory'] as String?,
      resolution: map['resolution'] as String?,
      localizedTitles: _parseLocalizedMap(map['localizedTitles']),
      localizedOverviews: _parseLocalizedMap(map['localizedOverviews']),
      // 扩展视频信息
      videoSource: map['videoSource'] as String?,
      videoCodec: map['videoCodec'] as String?,
      hdrFormat: map['hdrFormat'] as String?,
      audioFormat: map['audioFormat'] as String?,
      is3D: map['is3D'] == 1 || map['is3D'] == true,
      isRemux: map['isRemux'] == 1 || map['isRemux'] == true,
      // 扩展评分
      imdbId: map['imdbId'] as String?,
      imdbRating: (map['imdbRating'] as num?)?.toDouble(),
      metacriticRating: map['metacriticRating'] as int?,
      traktRating: (map['traktRating'] as num?)?.toDouble(),
      // 内容分级
      certification: map['certification'] as String?,
      // 媒体服务器相关
      serverType: map['serverType'] as String?,
      serverItemId: map['serverItemId'] as String?,
      scrapeSource: map['scrapeSource'] as String?,
      isWatched: map['isWatched'] == 1 || map['isWatched'] == true,
      playbackPositionTicks: map['playbackPositionTicks'] as int?,
      lastPlayedAt: map['lastPlayedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastPlayedAt'] as int)
          : null,
    );

  /// 解析多语言 Map（从 JSON 字符串或 Map）
  static Map<String, String>? _parseLocalizedMap(dynamic value) {
    if (value == null) return null;
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value) as Map<String, dynamic>;
        return decoded.map((k, v) => MapEntry(k, v.toString()));
      } on Exception {
        return null;
      }
    }
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    return null;
  }

  final String filePath;
  final String sourceId;
  final String fileName;
  MediaCategory category;
  ScrapeStatus scrapeStatus;
  int? tmdbId;
  String? doubanId; // 豆瓣 ID（字符串，如 "1291546"）
  String? title;
  String? originalTitle;
  int? year;
  String? overview;
  String? posterUrl;
  String? backdropUrl;
  double? rating;
  int? runtime;
  String? genres;
  String? countries; // 国家/地区（逗号分隔）
  String? director;
  String? cast;
  int? seasonNumber;
  int? episodeNumber;
  String? episodeTitle;
  DateTime? lastUpdated;
  String? thumbnailUrl; // 内置缩略图 URL（来自 NAS）
  String? generatedThumbnailUrl; // 生成的缩略图 URL（本地 file://）
  String? localPosterUrl; // 本地缓存的海报 URL（本地 file://，离线可用）
  int? fileSize; // 文件大小（字节）
  DateTime? fileModifiedTime; // 文件修改时间
  int? collectionId; // TMDB 电影系列 ID
  String? collectionName; // TMDB 电影系列名称
  String? collectionPosterUrl; // 电影系列海报 URL（TMDB 系列专属海报）
  String? collectionBackdropUrl; // 电影系列背景图 URL
  String? showDirectory; // 所属剧目录（TV 剧集专用，用于分组）
  String? movieDirectory; // 电影所在目录（用于目录系列识别）
  String? resolution; // 视频分辨率（4K, 1080p, 720p 等）

  /// 多语言标题（语言代码 -> 标题）
  /// 例如：{'zh-CN': '霸王别姬', 'en': 'Farewell My Concubine', 'ja': '覇王別姫'}
  Map<String, String>? localizedTitles;

  /// 多语言简介（语言代码 -> 简介）
  Map<String, String>? localizedOverviews;

  // === 扩展视频信息 ===

  String? videoSource; // 视频来源（BluRay, WEB-DL, HDTV 等）
  String? videoCodec; // 视频编码（HEVC, x265, AVC 等）
  String? hdrFormat; // HDR 格式（HDR10, Dolby Vision 等）
  String? audioFormat; // 音频格式（Atmos, DTS-HD MA 等）
  bool is3D; // 是否 3D 内容
  bool isRemux; // 是否 Remux 版本

  // === 扩展评分 ===

  String? imdbId; // IMDb ID
  double? imdbRating; // IMDb 评分
  int? metacriticRating; // Metacritic 评分（0-100）
  double? traktRating; // Trakt 评分

  // === 内容分级 ===

  String? certification; // 内容分级（PG, PG-13, R, NC-17, G 等）

  // === 媒体服务器相关 ===

  String? serverType; // 服务器类型 (jellyfin, emby, plex)
  String? serverItemId; // 服务器中的项目 ID
  String? scrapeSource; // 元数据来源 (tmdb, server, nfo, filename)
  bool isWatched; // 是否已观看
  int? playbackPositionTicks; // 播放位置（时间刻度）
  DateTime? lastPlayedAt; // 最后播放时间

  /// 海报显示优先级：
  /// 1. 本地缓存的海报（离线可用，file:// 路径）
  /// 2. TMDB 海报（需网络，但会被 CachedNetworkImage 缓存）
  /// 3. NAS 内置缩略图（需 NAS 连接）
  /// 4. 生成的视频缩略图（本地文件）
  ///
  /// 注意：localPosterUrl 始终指向本地 file:// 缓存路径，不会是 NAS 路径
  String? get displayPosterUrl {
    // 本地缓存优先（离线可用）
    if (localPosterUrl != null && localPosterUrl!.isNotEmpty) return localPosterUrl;
    // 网络 URL 作为备选
    if (posterUrl != null && posterUrl!.isNotEmpty) return posterUrl;
    if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty) return thumbnailUrl;
    if (generatedThumbnailUrl != null && generatedThumbnailUrl!.isNotEmpty) return generatedThumbnailUrl;
    return null;
  }

  /// 是否有元数据（已成功刮削数据）
  bool get hasMetadata => tmdbId != null || doubanId != null;

  /// 是否已完成刮削（成功或失败都算完成）
  bool get isScrapeDone =>
      scrapeStatus == ScrapeStatus.completed ||
      scrapeStatus == ScrapeStatus.failed ||
      scrapeStatus == ScrapeStatus.skipped;

  /// 是否正在刮削
  bool get isScraping => scrapeStatus == ScrapeStatus.scraping;

  /// 是否待刮削
  bool get isPendingScrape => scrapeStatus == ScrapeStatus.pending;

  /// 文件大小显示文本
  String get fileSizeText {
    if (fileSize == null || fileSize == 0) return '';
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (fileSize! >= gb) {
      return '${(fileSize! / gb).toStringAsFixed(2)} GB';
    } else if (fileSize! >= mb) {
      return '${(fileSize! / mb).toStringAsFixed(1)} MB';
    } else if (fileSize! >= kb) {
      return '${(fileSize! / kb).toStringAsFixed(0)} KB';
    }
    return '$fileSize B';
  }

  /// 显示标题（简单版本，兼容旧代码）
  String get displayTitle => title ?? fileName;

  /// 根据语言偏好获取标题
  ///
  /// [preferredLanguages] 语言代码优先级列表，例如 ['zh-CN', 'zh-TW', 'en']
  /// 返回优先级最高的可用标题，如果都没有则返回 title 或 originalTitle 或 fileName
  String getLocalizedTitle(List<String> preferredLanguages) {
    // 1. 尝试从多语言数据中按优先级查找
    if (localizedTitles != null && localizedTitles!.isNotEmpty) {
      for (final lang in preferredLanguages) {
        final localized = localizedTitles![lang];
        if (localized != null && localized.isNotEmpty) {
          return localized;
        }
        // 尝试语言前缀匹配（zh-CN 匹配 zh）
        final langPrefix = lang.split('-').first;
        for (final entry in localizedTitles!.entries) {
          if (entry.key.startsWith(langPrefix) && entry.value.isNotEmpty) {
            return entry.value;
          }
        }
      }
    }

    // 2. 检查主标题是否匹配偏好语言
    // 如果偏好中文且 title 包含中文字符，使用 title
    if (title != null && title!.isNotEmpty) {
      for (final lang in preferredLanguages) {
        if (lang.startsWith('zh') && _containsChinese(title!)) {
          return title!;
        }
        if (lang == 'ja' && _containsJapanese(title!)) {
          return title!;
        }
        if (lang == 'ko' && _containsKorean(title!)) {
          return title!;
        }
        // 英文或其他拉丁语系
        if ((lang == 'en' || lang.startsWith('en-')) && _isLatin(title!)) {
          return title!;
        }
      }
    }

    // 3. 检查是否有 original 偏好
    for (final lang in preferredLanguages) {
      if (lang == 'original' && originalTitle != null && originalTitle!.isNotEmpty) {
        return originalTitle!;
      }
    }

    // 4. 回退到默认标题
    return title ?? originalTitle ?? fileName;
  }

  /// 根据语言偏好获取简介
  String? getLocalizedOverview(List<String> preferredLanguages) {
    // 1. 尝试从多语言数据中按优先级查找
    if (localizedOverviews != null && localizedOverviews!.isNotEmpty) {
      for (final lang in preferredLanguages) {
        final localized = localizedOverviews![lang];
        if (localized != null && localized.isNotEmpty) {
          return localized;
        }
        // 尝试语言前缀匹配
        final langPrefix = lang.split('-').first;
        for (final entry in localizedOverviews!.entries) {
          if (entry.key.startsWith(langPrefix) && entry.value.isNotEmpty) {
            return entry.value;
          }
        }
      }
    }

    // 2. 回退到默认简介
    return overview;
  }

  /// 检查字符串是否包含中文字符
  static bool _containsChinese(String text) =>
      RegExp(r'[\u4e00-\u9fff]').hasMatch(text);

  /// 检查字符串是否包含日文字符（假名）
  static bool _containsJapanese(String text) =>
      RegExp(r'[\u3040-\u309f\u30a0-\u30ff]').hasMatch(text);

  /// 检查字符串是否包含韩文字符
  static bool _containsKorean(String text) =>
      RegExp(r'[\uac00-\ud7af]').hasMatch(text);

  /// 检查字符串是否主要是拉丁字符
  static bool _isLatin(String text) {
    // 使用 Unicode 范围检查：基本拉丁字母、拉丁扩展、常见标点符号
    final latinPattern = RegExp(r'^[\u0000-\u007F\u0080-\u00FF\u0100-\u017F]+$');
    return latinPattern.hasMatch(text);
  }

  /// 评分文本
  String get ratingText => rating != null ? rating!.toStringAsFixed(1) : '';

  /// 时长文本
  String get runtimeText {
    if (runtime == null || runtime == 0) return '';
    final hours = runtime! ~/ 60;
    final minutes = runtime! % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  /// 类型列表
  /// 注意：genres 可能使用 ' / '（Scraper）或 ', '（NFO）分隔
  List<String> get genreList =>
      genres?.split(RegExp(r'\s*[/,]\s*')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList() ?? [];

  /// 国家/地区列表
  List<String> get countryList => countries?.split(',').map((e) => e.trim()).toList() ?? [];

  /// 演员列表
  List<String> get castList => cast?.split(',').map((e) => e.trim()).toList() ?? [];

  /// 从 TMDB 电影详情更新
  void updateFromMovie(TmdbMovieDetail movie) {
    category = MediaCategory.movie;
    tmdbId = movie.id;
    title = movie.title;
    originalTitle = movie.originalTitle;
    year = movie.year;
    overview = movie.overview;
    posterUrl = movie.posterUrl;
    backdropUrl = movie.backdropUrl;
    rating = movie.voteAverage;
    runtime = movie.runtime;
    genres = movie.genresText;
    countries = movie.countriesText;
    director = movie.director?.name;
    cast = movie.cast.take(5).map((c) => c.name).join(', ');
    // 保存电影系列信息
    collectionId = movie.belongsToCollection?.id;
    collectionName = movie.belongsToCollection?.name;
    lastUpdated = DateTime.now();
  }

  /// 从 TMDB 电视剧详情更新
  void updateFromTvShow(TmdbTvDetail tv, {int? season, int? episode, String? epTitle}) {
    category = MediaCategory.tvShow;
    tmdbId = tv.id;
    title = tv.name;
    originalTitle = tv.originalName;
    year = tv.year;
    overview = tv.overview;
    posterUrl = tv.posterUrl;
    backdropUrl = tv.backdropUrl;
    rating = tv.voteAverage;
    runtime = tv.episodeRunTime.isNotEmpty ? tv.episodeRunTime.first : null;
    genres = tv.genresText;
    countries = tv.countriesText;
    cast = tv.cast.take(5).map((c) => c.name).join(', ');
    seasonNumber = season;
    episodeNumber = episode;
    episodeTitle = epTitle;
    lastUpdated = DateTime.now();
  }

  /// 从 TMDB 搜索结果更新
  void updateFromSearchResult(TmdbMediaItem item) {
    category = item.isMovie ? MediaCategory.movie : MediaCategory.tvShow;
    tmdbId = item.id;
    title = item.title;
    originalTitle = item.originalTitle;
    year = item.year;
    overview = item.overview;
    posterUrl = item.posterUrl;
    backdropUrl = item.backdropUrl;
    rating = item.voteAverage;
    lastUpdated = DateTime.now();
  }

  /// 唯一标识
  String get uniqueKey => '${sourceId}_$filePath';

  /// 转为 Map
  Map<String, dynamic> toMap() => {
      'filePath': filePath,
      'sourceId': sourceId,
      'fileName': fileName,
      'category': category.index,
      'scrapeStatus': scrapeStatus.index,
      'tmdbId': tmdbId,
      'doubanId': doubanId,
      'title': title,
      'originalTitle': originalTitle,
      'year': year,
      'overview': overview,
      'posterUrl': posterUrl,
      'backdropUrl': backdropUrl,
      'rating': rating,
      'runtime': runtime,
      'genres': genres,
      'countries': countries,
      'director': director,
      'cast': cast,
      'seasonNumber': seasonNumber,
      'episodeNumber': episodeNumber,
      'episodeTitle': episodeTitle,
      'lastUpdated': lastUpdated?.millisecondsSinceEpoch,
      'thumbnailUrl': thumbnailUrl,
      'generatedThumbnailUrl': generatedThumbnailUrl,
      'localPosterUrl': localPosterUrl,
      'fileSize': fileSize,
      'fileModifiedTime': fileModifiedTime?.millisecondsSinceEpoch,
      'collectionId': collectionId,
      'collectionName': collectionName,
      'collectionPosterUrl': collectionPosterUrl,
      'collectionBackdropUrl': collectionBackdropUrl,
      'showDirectory': showDirectory,
      'movieDirectory': movieDirectory,
      'resolution': resolution,
      'localizedTitles': localizedTitles != null ? jsonEncode(localizedTitles) : null,
      'localizedOverviews': localizedOverviews != null ? jsonEncode(localizedOverviews) : null,
      // 扩展视频信息
      'videoSource': videoSource,
      'videoCodec': videoCodec,
      'hdrFormat': hdrFormat,
      'audioFormat': audioFormat,
      'is3D': is3D ? 1 : 0,
      'isRemux': isRemux ? 1 : 0,
      // 扩展评分
      'imdbId': imdbId,
      'imdbRating': imdbRating,
      'metacriticRating': metacriticRating,
      'traktRating': traktRating,
      // 内容分级
      'certification': certification,
      // 媒体服务器相关
      'serverType': serverType,
      'serverItemId': serverItemId,
      'scrapeSource': scrapeSource,
      'isWatched': isWatched ? 1 : 0,
      'playbackPositionTicks': playbackPositionTicks,
      'lastPlayedAt': lastPlayedAt?.millisecondsSinceEpoch,
    };

  /// 复制
  VideoMetadata copyWith({
    String? filePath,
    String? sourceId,
    String? fileName,
    MediaCategory? category,
    ScrapeStatus? scrapeStatus,
    int? tmdbId,
    String? doubanId,
    String? title,
    String? originalTitle,
    int? year,
    String? overview,
    String? posterUrl,
    String? backdropUrl,
    double? rating,
    int? runtime,
    String? genres,
    String? countries,
    String? director,
    String? cast,
    int? seasonNumber,
    int? episodeNumber,
    String? episodeTitle,
    DateTime? lastUpdated,
    String? thumbnailUrl,
    String? generatedThumbnailUrl,
    String? localPosterUrl,
    int? fileSize,
    DateTime? fileModifiedTime,
    int? collectionId,
    String? collectionName,
    String? collectionPosterUrl,
    String? collectionBackdropUrl,
    String? showDirectory,
    String? movieDirectory,
    String? resolution,
    Map<String, String>? localizedTitles,
    Map<String, String>? localizedOverviews,
    // 扩展视频信息
    String? videoSource,
    String? videoCodec,
    String? hdrFormat,
    String? audioFormat,
    bool? is3D,
    bool? isRemux,
    // 扩展评分
    String? imdbId,
    double? imdbRating,
    int? metacriticRating,
    double? traktRating,
    // 内容分级
    String? certification,
    // 媒体服务器相关
    String? serverType,
    String? serverItemId,
    String? scrapeSource,
    bool? isWatched,
    int? playbackPositionTicks,
    DateTime? lastPlayedAt,
  }) => VideoMetadata(
      filePath: filePath ?? this.filePath,
      sourceId: sourceId ?? this.sourceId,
      fileName: fileName ?? this.fileName,
      category: category ?? this.category,
      scrapeStatus: scrapeStatus ?? this.scrapeStatus,
      tmdbId: tmdbId ?? this.tmdbId,
      doubanId: doubanId ?? this.doubanId,
      title: title ?? this.title,
      originalTitle: originalTitle ?? this.originalTitle,
      year: year ?? this.year,
      overview: overview ?? this.overview,
      posterUrl: posterUrl ?? this.posterUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      rating: rating ?? this.rating,
      runtime: runtime ?? this.runtime,
      genres: genres ?? this.genres,
      countries: countries ?? this.countries,
      director: director ?? this.director,
      cast: cast ?? this.cast,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      generatedThumbnailUrl: generatedThumbnailUrl ?? this.generatedThumbnailUrl,
      localPosterUrl: localPosterUrl ?? this.localPosterUrl,
      fileSize: fileSize ?? this.fileSize,
      fileModifiedTime: fileModifiedTime ?? this.fileModifiedTime,
      collectionId: collectionId ?? this.collectionId,
      collectionName: collectionName ?? this.collectionName,
      collectionPosterUrl: collectionPosterUrl ?? this.collectionPosterUrl,
      collectionBackdropUrl: collectionBackdropUrl ?? this.collectionBackdropUrl,
      showDirectory: showDirectory ?? this.showDirectory,
      movieDirectory: movieDirectory ?? this.movieDirectory,
      resolution: resolution ?? this.resolution,
      localizedTitles: localizedTitles ?? this.localizedTitles,
      localizedOverviews: localizedOverviews ?? this.localizedOverviews,
      // 扩展视频信息
      videoSource: videoSource ?? this.videoSource,
      videoCodec: videoCodec ?? this.videoCodec,
      hdrFormat: hdrFormat ?? this.hdrFormat,
      audioFormat: audioFormat ?? this.audioFormat,
      is3D: is3D ?? this.is3D,
      isRemux: isRemux ?? this.isRemux,
      // 扩展评分
      imdbId: imdbId ?? this.imdbId,
      imdbRating: imdbRating ?? this.imdbRating,
      metacriticRating: metacriticRating ?? this.metacriticRating,
      traktRating: traktRating ?? this.traktRating,
      // 内容分级
      certification: certification ?? this.certification,
      // 媒体服务器相关
      serverType: serverType ?? this.serverType,
      serverItemId: serverItemId ?? this.serverItemId,
      scrapeSource: scrapeSource ?? this.scrapeSource,
      isWatched: isWatched ?? this.isWatched,
      playbackPositionTicks: playbackPositionTicks ?? this.playbackPositionTicks,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    );

  /// 添加或更新多语言标题
  void addLocalizedTitle(String languageCode, String localizedTitle) {
    localizedTitles ??= {};
    localizedTitles![languageCode] = localizedTitle;
  }

  /// 添加或更新多语言简介
  void addLocalizedOverview(String languageCode, String localizedOverview) {
    localizedOverviews ??= {};
    localizedOverviews![languageCode] = localizedOverview;
  }

  /// 从 TMDB 数据更新多语言信息
  /// [languageCode] 用于获取此数据的语言代码
  void updateLocalizedFromTmdb(String languageCode, String? tmdbTitle, String? tmdbOverview) {
    if (tmdbTitle != null && tmdbTitle.isNotEmpty) {
      addLocalizedTitle(languageCode, tmdbTitle);
    }
    if (tmdbOverview != null && tmdbOverview.isNotEmpty) {
      addLocalizedOverview(languageCode, tmdbOverview);
    }
  }
}

/// 视频文件名解析结果
class VideoFileNameInfo {
  VideoFileNameInfo({
    required this.cleanTitle,
    this.year,
    this.season,
    this.episode,
    this.resolution,
    this.source,
    this.codec,
    this.hdrFormat,
    this.audioFormat,
    this.is3D = false,
    this.isRemux = false,
  });

  final String cleanTitle;
  final int? year;
  final int? season;
  final int? episode;
  final String? resolution; // 4K, 2160p, 1080p, 720p, 480p
  final String? source; // BluRay, WEB-DL, HDTV, DVDRip
  final String? codec; // HEVC, x265, AVC, x264
  final String? hdrFormat; // HDR, HDR10, HDR10+, Dolby Vision, DV
  final String? audioFormat; // Atmos, DTS-X, DTS-HD MA, TrueHD, DTS, AAC, AC3
  final bool is3D; // 3D 内容
  final bool isRemux; // Remux 版本

  bool get isTvShow => season != null || episode != null;
  bool get isMovie => !isTvShow;

  /// 是否是 4K 内容
  bool get is4K =>
      resolution?.toUpperCase() == '4K' ||
      resolution?.toUpperCase() == '2160P' ||
      resolution == '2160p';

  /// 是否是 HDR 内容
  bool get isHDR => hdrFormat != null && hdrFormat!.isNotEmpty;

  /// 是否是杜比视界
  bool get isDolbyVision =>
      (hdrFormat?.toUpperCase().contains('DOLBY') ?? false) ||
      hdrFormat?.toUpperCase() == 'DV';

  /// 是否是高清 (1080p+)
  bool get isHD =>
      is4K ||
      resolution?.toUpperCase() == '1080P' ||
      resolution == '1080p';

  /// 是否是蓝光
  bool get isBluRay =>
      (source?.toUpperCase().contains('BLU') ?? false) ||
      (source?.toUpperCase().contains('BD') ?? false) ||
      isRemux;
}

/// 视频文件名解析器
class VideoFileNameParser {
  static final _yearPattern = RegExp(r'[\[\(]?((?:19|20)\d{2})[\]\)]?');

  /// 中文数字映射
  static const _chineseNumbers = {
    '零': 0, '〇': 0,
    '一': 1, '壹': 1,
    '二': 2, '贰': 2, '两': 2,
    '三': 3, '叁': 3,
    '四': 4, '肆': 4,
    '五': 5, '伍': 5,
    '六': 6, '陆': 6,
    '七': 7, '柒': 7,
    '八': 8, '捌': 8,
    '九': 9, '玖': 9,
    '十': 10, '拾': 10,
    '百': 100, '佰': 100,
    '千': 1000, '仟': 1000,
  };

  /// 解析中文数字或阿拉伯数字
  ///
  /// 支持的格式：
  /// - 阿拉伯数字：1, 01, 123
  /// - 简单中文：一, 二, 十, 百
  /// - 复合中文：十二, 二十一, 一百二十三
  static int? _parseChineseNumber(String str) {
    // 先尝试解析阿拉伯数字
    final arabicNum = int.tryParse(str);
    if (arabicNum != null) return arabicNum;

    // 解析中文数字
    if (str.isEmpty) return null;

    var result = 0;
    var temp = 0;
    var section = 0; // 当前节（千位以下）

    for (var i = 0; i < str.length; i++) {
      final char = str[i];
      final num = _chineseNumbers[char];

      if (num == null) continue;

      if (num == 1000) {
        // 千
        if (temp == 0) temp = 1;
        section += temp * 1000;
        temp = 0;
      } else if (num == 100) {
        // 百
        if (temp == 0) temp = 1;
        section += temp * 100;
        temp = 0;
      } else if (num == 10) {
        // 十
        if (temp == 0) temp = 1;
        section += temp * 10;
        temp = 0;
      } else {
        temp = num;
      }
    }

    result = section + temp;
    return result > 0 ? result : null;
  }

  /// 剧集模式（按优先级排序，从最精确到最宽松）
  ///
  /// 支持的格式：
  /// 【标准格式】
  /// - S01E01, s01e01, S01.E01, S01 E01 (标准格式，支持空格和点分隔)
  /// - 1x01, 01x01 (旧式格式)
  /// - Season 1 Episode 1, Season.1.Episode.1 (完整拼写)
  ///
  /// 【中文格式】
  /// - 第X季第X集, 第X季.第X集, 第1季 第1集
  /// - 第X集, 第X话, 第X回 (只有集号)
  /// - 第一集, 第二十一话 (中文数字)
  /// - 01集, 01话, 01回 (数字直接跟单位)
  ///
  /// 【日本动画格式】
  /// - #01, ＃01 (井号)
  /// - 01話, 01话 (数字+話/话)
  /// - [01], 【01】, (01), （01） (各种括号)
  /// - OVA01, OAD01, SP01, 特典01 (特典格式)
  /// - Vol.01, Vol 01 (卷号)
  ///
  /// 【英文格式】
  /// - EP01, ep01, E01, Ep.01 (集号前缀)
  /// - Part 1, Part.1, Pt.1 (部分)
  /// - Chapter 01, Ch.01 (章节)
  ///
  /// 【港剧特殊格式】
  /// - 剧名.S21.HD1080p (S后跟数字，再跟分辨率标记，S表示集号而非季号)
  ///
  /// 【紧凑格式】
  /// - 101, 201, 1201 (3-4位数，首位是季号: 1季01集, 12季01集)
  ///
  /// 【末尾数字】
  /// - 剧名.01, 剧名 - 01, 剧名_01 (文件名末尾的数字)
  static final _tvShowPattern = RegExp(
    // === 高优先级：带季号的精确格式 ===
    r'[Ss](\d{1,2})[\s._-]*[Ee](\d{1,3})'   // G1,G2: S01E01, S01.E01, S01 E01
    r'|(\d{1,2})x(\d{1,3})'                  // G3,G4: 1x01, 01x01
    r'|[Ss]eason[\s._-]*(\d{1,2})[\s._-]*[Ee]pisode[\s._-]*(\d{1,3})' // G5,G6: Season 1 Episode 1
    r'|第(\d+)季[\s._]*第(\d+)[集话回]'       // G7,G8: 第1季第1集/话/回

    // === 中优先级：只有集号的格式 ===
    r'|第([一二三四五六七八九十百千\d]+)[集话回期]' // G9: 第X集/话/回/期（中文数字）
    r'|[Ee][Pp]?[\s._]*(\d{1,3})(?![0-9pP])' // G10: EP01, E01, Ep.01
    r'|(?:^|[\s._-])(\d{1,3})[集话回話]'      // G11: 01集, 01话, 01回, 01話
    r'|[#＃](\d{1,3})'                       // G12: #01, ＃01 (日本动画常用)

    // === 括号包裹格式 ===
    r'|[\[【\(（](\d{1,3})[\]】\)）]'         // G13: [01], 【01】, (01), （01）

    // === 特典/卷/章节格式 ===
    r'|(?:OVA|OAD|SP|特典|番外)[\s._-]*(\d{1,2})' // G14: OVA01, SP01, 特典01
    r'|[Vv]ol(?:ume)?[\s._-]*(\d{1,2})'      // G15: Vol.01, Volume 01
    r'|(?:Part|Pt)[\s._-]*(\d{1,2})'         // G16: Part 1, Pt.1
    r'|(?:Chapter|Ch)[\s._-]*(\d{1,3})'      // G17: Chapter 01, Ch.01

    // === 港剧格式：.S数字.分辨率（S表示集号，不是季号）===
    r'|[\s._-][Ss](\d{1,3})[\s._-](?:HD|4K|2160|1080|720|480)' // G18: .S21.HD1080p

    // === 紧凑数字格式（仅限3位数，避免匹配年份）===
    r'|(?:^|[\s._-])(\d{3})(?:[\s._-]|$)'    // G19: 101=S1E01（仅3位数，4位可能是年份）

    // === 最低优先级：末尾数字（最宽松）===
    r'|[\s._-](\d{1,3})$',                   // G20: 末尾集号 .01, -01, _01
    caseSensitive: false,
  );

  static final _resolutionPattern = RegExp(
    '(4K|2160[pP]|1080[pP]|720[pP]|480[pP])',
    caseSensitive: false,
  );
  static final _sourcePattern = RegExp(
    '(BluRay|BDRip|WEB-?DL|WEBRip|HDRip|DVDRip|HDTV)',
    caseSensitive: false,
  );
  static final _codecPattern = RegExp(
    r'(x264|x265|HEVC|H\.?264|H\.?265|AVC|VP9|AV1)',
    caseSensitive: false,
  );

  /// HDR 格式匹配
  static final _hdrPattern = RegExp(
    r'(Dolby[\s._-]*Vision|DV|DoVi|HDR10\+?|HDR|HLG|PQ)',
    caseSensitive: false,
  );

  /// 音频格式匹配
  static final _audioPattern = RegExp(
    r'(Atmos|DTS[\s._-]?X|DTS[\s._-]?HD[\s._-]?MA|TrueHD|DTS|DD\+?|EAC3|AC3|AAC|FLAC|LPCM|PCM)',
    caseSensitive: false,
  );

  /// 3D 内容匹配
  // ignore: non_constant_identifier_names
  static final _3DPattern = RegExp(
    '(3D|SBS|HSBS|TAB|HTAB|OU|HOU)',
    caseSensitive: false,
  );

  /// Remux 匹配
  static final _remuxPattern = RegExp(
    r'(REMUX|UHD[\s._-]?Remux|BD[\s._-]?Remux)',
    caseSensitive: false,
  );
  static final _cleanupPattern = RegExp(
    r'[\[\]\(\)\{\}]|\.(?=\S)|_|-(?=\s)|'
    '(?:BluRay|BDRip|WEB-?DL|WEBRip|HDRip|DVDRip|HDTV|'
    r'x264|x265|HEVC|H\.?264|H\.?265|AVC|AAC|AC3|DTS|'
    '4K|2160p|1080p|720p|480p|'
    r'PROPER|REPACK|EXTENDED|UNRATED|DIRECTORS\.CUT|'
    '中英字幕|中文字幕|双语字幕|简体|繁体|'
    'RARBG|YTS|YIFY|FGT|EVO|SPARKS)',
    caseSensitive: false,
  );

  /// 解析视频文件名
  static VideoFileNameInfo parse(String fileName) {
    // 移除扩展名
    final name = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');

    // 提取年份
    int? year;
    final yearMatch = _yearPattern.firstMatch(name);
    if (yearMatch != null) {
      year = int.tryParse(yearMatch.group(1) ?? '');
    }

    // 检测日期/时间戳样式（录屏工具常用），如：
    //   bandicam 2025-04-29 11-20-31-308.mp4
    //   2024_01_15_14-30-22.mp4
    // 命中时跳过低优先级的紧凑/末尾数字 TV 模式，避免把毫秒/秒识别成 SxxEyy。
    final looksLikeTimestamp = RegExp(
      r'(?:19|20)\d{2}[\s._-]\d{1,2}[\s._-]\d{1,2}[\s._-]\d{1,2}',
    ).hasMatch(name);

    // 提取剧集信息
    int? season;
    int? episode;
    final tvMatch = _tvShowPattern.firstMatch(name);
    if (tvMatch != null) {
      // === 高优先级：带季号的精确格式 ===
      if (tvMatch.group(1) != null && tvMatch.group(2) != null) {
        // G1,G2: S01E01, S01.E01, S01 E01
        season = int.tryParse(tvMatch.group(1)!);
        episode = int.tryParse(tvMatch.group(2)!);
      } else if (tvMatch.group(3) != null && tvMatch.group(4) != null) {
        // G3,G4: 1x01, 01x01
        season = int.tryParse(tvMatch.group(3)!);
        episode = int.tryParse(tvMatch.group(4)!);
      } else if (tvMatch.group(5) != null && tvMatch.group(6) != null) {
        // G5,G6: Season 1 Episode 1
        season = int.tryParse(tvMatch.group(5)!);
        episode = int.tryParse(tvMatch.group(6)!);
      } else if (tvMatch.group(7) != null && tvMatch.group(8) != null) {
        // G7,G8: 第1季第1集/话/回
        season = int.tryParse(tvMatch.group(7)!);
        episode = int.tryParse(tvMatch.group(8)!);
      }
      // === 中优先级：只有集号的格式 ===
      else if (tvMatch.group(9) != null) {
        // G9: 第X集/话/回/期（中文数字）
        episode = _parseChineseNumber(tvMatch.group(9)!);
        season = 1;
      } else if (tvMatch.group(10) != null) {
        // G10: EP01, E01, Ep.01
        episode = int.tryParse(tvMatch.group(10)!);
        season = 1;
      } else if (tvMatch.group(11) != null) {
        // G11: 01集, 01话, 01回, 01話
        episode = int.tryParse(tvMatch.group(11)!);
        season = 1;
      } else if (tvMatch.group(12) != null) {
        // G12: #01, ＃01
        episode = int.tryParse(tvMatch.group(12)!);
        season = 1;
      }
      // === 括号包裹格式 ===
      else if (tvMatch.group(13) != null) {
        // G13: [01], 【01】, (01), （01）
        episode = int.tryParse(tvMatch.group(13)!);
        season = 1;
      }
      // === 特典/卷/章节格式 ===
      else if (tvMatch.group(14) != null) {
        // G14: OVA01, SP01, 特典01, 番外01 → season = 0 表示特典
        episode = int.tryParse(tvMatch.group(14)!);
        season = 0;
      } else if (tvMatch.group(15) != null) {
        // G15: Vol.01, Volume 01 → 作为季号处理
        season = int.tryParse(tvMatch.group(15)!);
        episode = 1;
      } else if (tvMatch.group(16) != null) {
        // G16: Part 1, Pt.1
        episode = int.tryParse(tvMatch.group(16)!);
        season = 1;
      } else if (tvMatch.group(17) != null) {
        // G17: Chapter 01, Ch.01
        episode = int.tryParse(tvMatch.group(17)!);
        season = 1;
      }
      // === 港剧格式：.S数字.分辨率（S表示集号，不是季号）===
      else if (tvMatch.group(18) != null) {
        // G18: .S21.HD1080p - S后面的数字是集号
        episode = int.tryParse(tvMatch.group(18)!);
        season = 1;
      }
      // === 紧凑数字格式（仅限3位数）===
      else if (tvMatch.group(19) != null && !looksLikeTimestamp) {
        // G19: 101=S1E01（仅3位数）
        final compact = tvMatch.group(19)!;
        final compactNum = int.tryParse(compact);
        if (compactNum != null && compact.length == 3) {
          // 101 → S1E01
          season = compactNum ~/ 100;
          episode = compactNum % 100;
          // 验证季号合理性（1-9）
          if (season < 1 || season > 9) {
            season = null;
            episode = null;
          }
        }
      }
      // === 最低优先级：末尾数字 ===
      else if (tvMatch.group(20) != null && !looksLikeTimestamp) {
        // G20: 末尾集号 .01, -01, _01
        episode = int.tryParse(tvMatch.group(20)!);
        season = 1;
      }
    }

    // 提取分辨率
    final resolutionMatch = _resolutionPattern.firstMatch(name);
    final resolution = resolutionMatch?.group(1);

    // 提取来源
    final sourceMatch = _sourcePattern.firstMatch(name);
    final source = sourceMatch?.group(1);

    // 提取编码
    final codecMatch = _codecPattern.firstMatch(name);
    final codec = codecMatch?.group(1);

    // 提取 HDR 格式
    final hdrMatch = _hdrPattern.firstMatch(name);
    var hdrFormat = hdrMatch?.group(1);
    // 规范化 HDR 格式名称
    if (hdrFormat != null) {
      final upper = hdrFormat.toUpperCase().replaceAll(RegExp(r'[\s._-]+'), '');
      if (upper.contains('DOLBY') || upper == 'DV' || upper == 'DOVI') {
        hdrFormat = 'Dolby Vision';
      } else if (upper == 'HDR10+') {
        hdrFormat = 'HDR10+';
      } else if (upper == 'HDR10' || upper == 'HDR') {
        hdrFormat = 'HDR10';
      } else if (upper == 'HLG') {
        hdrFormat = 'HLG';
      }
    }

    // 提取音频格式
    final audioMatch = _audioPattern.firstMatch(name);
    var audioFormat = audioMatch?.group(1);
    // 规范化音频格式名称
    if (audioFormat != null) {
      final upper = audioFormat.toUpperCase().replaceAll(RegExp(r'[\s._-]+'), '');
      if (upper == 'ATMOS') {
        audioFormat = 'Atmos';
      } else if (upper == 'DTSX') {
        audioFormat = 'DTS:X';
      } else if (upper == 'DTSHDMA') {
        audioFormat = 'DTS-HD MA';
      } else if (upper == 'TRUEHD') {
        audioFormat = 'TrueHD';
      } else if (upper == 'DTS') {
        audioFormat = 'DTS';
      } else if (upper == 'DD+' || upper == 'EAC3') {
        audioFormat = 'DD+';
      } else if (upper == 'DD' || upper == 'AC3') {
        audioFormat = 'AC3';
      } else if (upper == 'AAC') {
        audioFormat = 'AAC';
      } else if (upper == 'FLAC') {
        audioFormat = 'FLAC';
      }
    }

    // 检测 3D 内容
    final is3D = _3DPattern.hasMatch(name);

    // 检测 Remux
    final isRemux = _remuxPattern.hasMatch(name);

    // 清理标题
    var cleanTitle = name;

    // 移除年份后的所有内容（对于电影）
    if (year != null && season == null) {
      final yearIndex = name.indexOf(yearMatch!.group(0)!);
      if (yearIndex > 0) {
        cleanTitle = name.substring(0, yearIndex);
      }
    }

    // 移除剧集信息后的内容
    if (tvMatch != null) {
      final matchIndex = name.indexOf(tvMatch.group(0)!);
      if (matchIndex > 0) {
        cleanTitle = name.substring(0, matchIndex);
      }
    }

    // 清理特殊字符和关键词
    cleanTitle = cleanTitle
        .replaceAll(_cleanupPattern, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return VideoFileNameInfo(
      cleanTitle: cleanTitle,
      year: year,
      season: season,
      episode: episode,
      resolution: resolution,
      source: source,
      codec: codec,
      hdrFormat: hdrFormat,
      audioFormat: audioFormat,
      is3D: is3D,
      isRemux: isRemux,
    );
  }
}
