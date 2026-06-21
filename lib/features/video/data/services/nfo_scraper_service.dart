import 'dart:convert';

import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:xml/xml.dart';

/// NFO 刮削信息
class NfoMetadata {
  NfoMetadata({
    this.title,
    this.originalTitle,
    this.year,
    this.plot,
    this.rating,
    this.runtime,
    this.genres,
    this.countries,
    this.director,
    this.actors,
    this.studio,
    this.tmdbId,
    this.imdbId,
    this.posterPath,
    this.fanartPath,
    this.thumbPath,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeTitle,
    this.aired,
    this.setName,
    this.setOverview,
    this.setTmdbId,
  });

  final String? title;
  final String? originalTitle;
  final int? year;
  final String? plot;
  final double? rating;
  final int? runtime;
  final List<String>? genres;
  final List<String>? countries; // 国家/地区列表
  final String? director;
  final List<String>? actors;
  final String? studio;
  final int? tmdbId;
  final String? imdbId;
  final String? posterPath;   // 本地海报路径
  final String? fanartPath;   // 本地背景图路径
  final String? thumbPath;    // 本地缩略图路径
  final int? seasonNumber;
  final int? episodeNumber;
  final String? episodeTitle;
  final String? aired;
  final String? setName;      // 电影系列名称（来自 <set><name>...）
  final String? setOverview;  // 电影系列描述（来自 <set><overview>...）
  final int? setTmdbId;       // 电影系列 TMDB ID（来自 <set><tmdbcolid>...）

  bool get hasData => title != null || tmdbId != null;

  /// 转换为 VideoMetadata
  VideoMetadata toVideoMetadata({
    required String filePath,
    required String sourceId,
    required String fileName,
    String? thumbnailUrl,
  }) => VideoMetadata(
      filePath: filePath,
      sourceId: sourceId,
      fileName: fileName,
      category: seasonNumber != null || episodeNumber != null
          ? MediaCategory.tvShow
          : MediaCategory.movie,
      tmdbId: tmdbId,
      title: title,
      originalTitle: originalTitle,
      year: year,
      overview: plot,
      rating: rating,
      runtime: runtime,
      genres: genres?.join(' / '),
      countries: countries?.join(', '),
      director: director,
      cast: actors?.take(5).join(', '),
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      episodeTitle: episodeTitle,
      thumbnailUrl: thumbnailUrl,
      lastUpdated: DateTime.now(),
    );
}

/// NFO 刮削服务
/// 用于解析视频同级目录下的 NFO 刮削文件和本地图片
class NfoScraperService {
  factory NfoScraperService() => _instance ??= NfoScraperService._();
  NfoScraperService._();

  static NfoScraperService? _instance;

  /// 支持的 NFO 文件扩展名
  static const _nfoExtensions = ['.nfo'];

  /// 支持的图片扩展名
  static const _imageExtensions = ['.jpg', '.jpeg', '.png', '.webp'];

  /// 海报文件名模式
  static const _posterPatterns = ['poster', 'cover', 'folder'];

  /// 背景图文件名模式
  static const _fanartPatterns = ['fanart', 'backdrop', 'background', 'art'];

  /// 缩略图文件名模式
  static const _thumbPatterns = ['thumb', 'thumbnail'];

  /// 快速解析目录中的 NFO 基础信息（用于扫描阶段）
  ///
  /// 只解析当前目录的 NFO 文件，不向上查找父目录
  /// 返回基础信息：标题、年份、评分、海报路径
  /// 这是轻量级操作，适合在扫描阶段批量调用
  Future<NfoMetadata?> quickParseFromDirectory({
    required NasFileSystem fileSystem,
    required List<FileItem> directoryItems,
    required String videoDir,
    required String videoBaseName,
  }) async {
    try {
      // 1. 查找视频同名 NFO 或 movie.nfo/tvshow.nfo
      NfoMetadata? nfoData;

      for (final file in directoryItems) {
        if (file.isDirectory) continue;

        final fileName = file.name.toLowerCase();

        // 优先视频同名 NFO
        if (_isMatchingNfo(fileName, videoBaseName)) {
          try {
            final content = await _readFileAsString(fileSystem, file.path);
            nfoData = _parseNfoContent(content);
            break;
          } on Exception catch (e) {
            logger.w('NfoScraperService: 快速解析 NFO 失败 ${file.name}', e);
          }
        }

        // 其次 movie.nfo 或 tvshow.nfo
        if (nfoData == null &&
            (fileName == 'movie.nfo' || fileName == 'tvshow.nfo')) {
          try {
            final content = await _readFileAsString(fileSystem, file.path);
            nfoData = _parseNfoContent(content);
          } on Exception catch (e) {
            logger.w('NfoScraperService: 快速解析 $fileName 失败', e);
          }
        }
      }

      if (nfoData == null || !nfoData.hasData) {
        return null;
      }

      // 2. 查找本地海报图片
      final images = await _findLocalImages(
        directoryItems,
        videoBaseName,
        fileSystem,
        videoDir,
      );

      // 返回合并后的数据
      return NfoMetadata(
        title: nfoData.title,
        originalTitle: nfoData.originalTitle,
        year: nfoData.year,
        rating: nfoData.rating,
        tmdbId: nfoData.tmdbId,
        genres: nfoData.genres,
        seasonNumber: nfoData.seasonNumber,
        episodeNumber: nfoData.episodeNumber,
        posterPath: images['poster'],
        fanartPath: images['fanart'],
        thumbPath: images['thumb'],
      );
    } on Exception catch (e) {
      logger.w('NfoScraperService: 快速解析目录失败', e);
      return null;
    }
  }

  /// 获取视频同级目录下的刮削信息
  ///
  /// 查找顺序：
  /// 1. 视频同名 NFO 文件（如 S01E01.nfo）
  /// 2. 当前目录的 episode.nfo 或 movie.nfo
  /// 3. 父目录的 tvshow.nfo（用于获取剧集整体信息）
  /// 4. 祖父目录的 tvshow.nfo（适用于 Season 子目录结构）
  Future<NfoMetadata?> scrapeFromDirectory({
    required NasFileSystem fileSystem,
    required String videoPath,
    required String videoFileName,
  }) async {
    try {
      // 获取视频所在目录
      final videoDir = _getParentPath(videoPath);
      final videoBaseName = _getBaseName(videoFileName);

      // logger.d('NfoScraperService: 扫描目录 $videoDir 查找 $videoBaseName 的刮削信息'); // 减少日志输出

      // 列出目录内容
      final files = await fileSystem.listDirectory(videoDir);

      // 1. 查找视频同名 NFO 文件或 episode.nfo
      var episodeNfo = await _findEpisodeNfo(fileSystem, files, videoBaseName);

      // 2. 如果没找到，查找 movie.nfo
      episodeNfo ??= await _findMovieNfo(fileSystem, files);

      // 3. 查找本地图片（当前目录）
      final localImages = await _findLocalImages(
        files,
        videoBaseName,
        fileSystem,
        videoDir,
      );

      // 4. 向上查找 tvshow.nfo（获取剧集整体信息）
      NfoMetadata? showNfo;
      Map<String, String?>? showImages;

      // 判断是否可能是剧集（有季集信息或文件名匹配剧集模式）
      final isPossibleTvShow = episodeNfo?.seasonNumber != null ||
          episodeNfo?.episodeNumber != null ||
          _looksLikeTvShow(videoFileName);

      if (isPossibleTvShow) {
        final (nfo, images) = await _findShowNfoInParents(
          fileSystem,
          videoDir,
        );
        showNfo = nfo;
        showImages = images;
      }

      // 5. 合并信息（单集信息 + 剧集整体信息）
      return _mergeNfoData(
        episodeNfo: episodeNfo,
        showNfo: showNfo,
        localImages: localImages,
        showImages: showImages,
      );
    } on Exception catch (e) {
      logger.e('NfoScraperService: 刮削失败', e);
      return null;
    }
  }

  /// 查找单集 NFO 文件
  Future<NfoMetadata?> _findEpisodeNfo(
    NasFileSystem fileSystem,
    List<FileItem> files,
    String videoBaseName,
  ) async {
    // 优先查找与视频同名的 NFO 文件
    for (final file in files) {
      if (file.isDirectory) continue;

      final fileName = file.name.toLowerCase();
      if (_isMatchingNfo(fileName, videoBaseName)) {
        try {
          final content = await _readFileAsString(fileSystem, file.path);
          // logger.d('NfoScraperService: 找到匹配的 NFO 文件 ${file.name}'); // 减少日志输出
          return _parseNfoContent(content);
        } on Exception catch (e) {
          logger.w('NfoScraperService: 读取 NFO 文件失败 ${file.name}', e);
        }
      }
    }

    // 查找 episode.nfo
    for (final file in files) {
      if (file.isDirectory) continue;

      if (file.name.toLowerCase() == 'episode.nfo') {
        try {
          final content = await _readFileAsString(fileSystem, file.path);
          // logger.d('NfoScraperService: 找到 episode.nfo'); // 减少日志输出
          return _parseNfoContent(content);
        } on Exception catch (e) {
          logger.w('NfoScraperService: 读取 episode.nfo 失败', e);
        }
      }
    }

    return null;
  }

  /// 查找电影 NFO 文件
  Future<NfoMetadata?> _findMovieNfo(
    NasFileSystem fileSystem,
    List<FileItem> files,
  ) async {
    for (final file in files) {
      if (file.isDirectory) continue;

      final fileName = file.name.toLowerCase();
      if (fileName == 'movie.nfo' || fileName == 'tvshow.nfo') {
        try {
          final content = await _readFileAsString(fileSystem, file.path);
          // logger.d('NfoScraperService: 找到 $fileName'); // 减少日志输出
          return _parseNfoContent(content);
        } on Exception catch (e) {
          logger.w('NfoScraperService: 读取 $fileName 失败', e);
        }
      }
    }
    return null;
  }

  /// 向上查找父目录中的 tvshow.nfo
  ///
  /// 适用于以下目录结构：
  /// /TV Shows/Breaking Bad/tvshow.nfo
  /// /TV Shows/Breaking Bad/Season 1/S01E01.mp4
  ///
  /// 从 Season 1 目录向上查找，最多查找 [maxLevels] 级
  Future<(NfoMetadata?, Map<String, String?>?)> _findShowNfoInParents(
    NasFileSystem fileSystem,
    String startDir,
    {int maxLevels = 2,}
  ) async {
    var currentDir = startDir;

    for (var level = 0; level < maxLevels; level++) {
      // 向上一级
      final parentDir = _getParentPath(currentDir);
      if (parentDir.isEmpty || parentDir == currentDir || parentDir == '/') {
        break;
      }
      currentDir = parentDir;

      try {
        final files = await fileSystem.listDirectory(currentDir);

        // 查找 tvshow.nfo
        for (final file in files) {
          if (file.isDirectory) continue;

          if (file.name.toLowerCase() == 'tvshow.nfo') {
            try {
              final content = await _readFileAsString(fileSystem, file.path);
              final nfo = _parseNfoContent(content);
              logger.i('NfoScraperService: 在父目录找到 tvshow.nfo: $currentDir');

              // 同时查找剧集级别的图片
              final images = await _findLocalImages(
                files,
                '', // 不匹配特定视频名
                fileSystem,
                currentDir,
              );

              return (nfo, images);
            } on Exception catch (e) {
              logger.w('NfoScraperService: 读取 tvshow.nfo 失败', e);
            }
          }
        }
      } on Exception catch (e) {
        logger.w('NfoScraperService: 列出父目录失败 $currentDir', e);
      }
    }

    return (null, null);
  }

  /// 判断文件名是否像剧集
  bool _looksLikeTvShow(String fileName) {
    final lowerName = fileName.toLowerCase();
    // 匹配常见剧集命名模式
    return RegExp(r's\d+e\d+|第.+[季部]|第.+集|\d+x\d+', caseSensitive: false)
        .hasMatch(lowerName);
  }

  /// 合并单集信息和剧集整体信息
  NfoMetadata? _mergeNfoData({
    NfoMetadata? episodeNfo,
    NfoMetadata? showNfo,
    Map<String, String?> localImages = const {},
    Map<String, String?>? showImages,
  }) {
    // 如果都没有数据，返回 null
    if (episodeNfo == null && showNfo == null) {
      // logger.d('NfoScraperService: 未找到任何 NFO 文件'); // 减少日志输出
      return null;
    }

    // 优先使用单集信息，缺失的从剧集信息补充
    final ep = episodeNfo;
    final show = showNfo;

    // 图片优先使用当前目录的，没有则使用剧集目录的
    final posterPath = localImages['poster'] ?? showImages?['poster'];
    final fanartPath = localImages['fanart'] ?? showImages?['fanart'];
    final thumbPath = localImages['thumb'] ?? showImages?['thumb'];

    return NfoMetadata(
      // 单集专属信息
      episodeNumber: ep?.episodeNumber,
      seasonNumber: ep?.seasonNumber,
      episodeTitle: ep?.episodeTitle ?? ep?.title,
      aired: ep?.aired,

      // 优先单集，回退到剧集
      title: show?.title ?? ep?.title, // 剧集标题优先使用 tvshow.nfo
      originalTitle: show?.originalTitle ?? ep?.originalTitle,
      year: show?.year ?? ep?.year,
      plot: ep?.plot ?? show?.plot, // 剧情优先使用单集的
      rating: show?.rating ?? ep?.rating, // 评分使用剧集整体的
      runtime: ep?.runtime ?? show?.runtime,
      genres: show?.genres ?? ep?.genres,
      countries: show?.countries ?? ep?.countries, // 国家/地区信息
      director: ep?.director ?? show?.director,
      actors: show?.actors ?? ep?.actors,
      studio: show?.studio ?? ep?.studio,

      // TMDB ID 优先使用剧集的（便于后续查询季集信息）
      tmdbId: show?.tmdbId ?? ep?.tmdbId,
      imdbId: show?.imdbId ?? ep?.imdbId,

      // 图片路径
      posterPath: posterPath,
      fanartPath: fanartPath,
      thumbPath: thumbPath,
    );
  }

  /// 检查是否是匹配的 NFO 文件
  bool _isMatchingNfo(String fileName, String videoBaseName) {
    for (final ext in _nfoExtensions) {
      if (fileName == '${videoBaseName.toLowerCase()}$ext') {
        return true;
      }
    }
    return false;
  }

  /// 读取文件内容为字符串
  Future<String> _readFileAsString(NasFileSystem fileSystem, String path) async {
    final stream = await fileSystem.getFileStream(path);
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
      // 限制文件大小，防止读取超大文件
      if (bytes.length > 1024 * 1024) { // 1MB 限制
        throw Exception(appL10n.nfoScraperServiceFileTooLarge);
      }
    }
    return utf8.decode(bytes);
  }

  /// 获取父目录路径
  String _getParentPath(String path) {
    // 处理 Windows 和 Unix 路径分隔符
    final lastSeparator = path.lastIndexOf('/');
    final lastBackslash = path.lastIndexOf(r'\');
    final separator = lastSeparator > lastBackslash ? lastSeparator : lastBackslash;

    if (separator > 0) {
      return path.substring(0, separator);
    }
    return path;
  }

  /// 获取文件基础名（不含扩展名）
  String _getBaseName(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex > 0) {
      return fileName.substring(0, dotIndex);
    }
    return fileName;
  }

  /// 解析 NFO 内容
  NfoMetadata _parseNfoContent(String content) {
    try {
      final document = XmlDocument.parse(content);
      final root = document.rootElement;

      // 判断根元素类型
      final rootName = root.name.local.toLowerCase();
      final isEpisode = rootName == 'episodedetails';

      // 始终尝试解析 season 和 episode 元素
      // 即使根元素不是 episodedetails，NFO 中也可能包含这些信息
      final seasonNumber = _parseInt(_getElementText(root, 'season'));
      final episodeNumber = _parseInt(_getElementText(root, 'episode'));

      // 如果有季集号，则视为剧集类型
      final hasEpisodeInfo = seasonNumber != null || episodeNumber != null;

      return NfoMetadata(
        title: _getElementText(root, 'title'),
        originalTitle: _getElementText(root, 'originaltitle'),
        year: _parseYear(root),
        plot: _getElementText(root, 'plot') ?? _getElementText(root, 'outline'),
        rating: _parseRating(root),
        runtime: _parseInt(_getElementText(root, 'runtime')),
        genres: _getGenres(root),
        countries: _getCountries(root),
        director: _getElementText(root, 'director'),
        actors: _getActors(root),
        studio: _getElementText(root, 'studio'),
        tmdbId: _parseTmdbId(root),
        imdbId: _getElementText(root, 'imdbid') ?? _getElementText(root, 'imdb'),
        // 始终解析季集号，不限制于 episodedetails 根元素
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        episodeTitle: (isEpisode || hasEpisodeInfo)
            ? _getElementText(root, 'title')
            : null,
        aired: _getElementText(root, 'aired') ?? _getElementText(root, 'premiered'),
        setName: _parseSetName(root),
        setOverview: _parseSetOverview(root),
        setTmdbId: _parseSetTmdbId(root),
      );
    } on Exception catch (e) {
      logger.e('NfoScraperService: 解析 NFO XML 失败', e);
      return NfoMetadata();
    }
  }

  /// 获取元素文本
  String? _getElementText(XmlElement root, String name) {
    try {
      final element = root.findElements(name).firstOrNull;
      if (element != null) {
        final text = element.innerText.trim();
        return text.isNotEmpty ? text : null;
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'NFO 元素 $name 读取失败');
    }
    return null;
  }

  /// 解析年份
  int? _parseYear(XmlElement root) {
    // 尝试从 year 元素获取
    final yearStr = _getElementText(root, 'year');
    if (yearStr != null) {
      return int.tryParse(yearStr);
    }

    // 尝试从 premiered 或 aired 获取
    final premiered = _getElementText(root, 'premiered') ??
        _getElementText(root, 'aired') ??
        _getElementText(root, 'releasedate');
    if (premiered != null && premiered.length >= 4) {
      return int.tryParse(premiered.substring(0, 4));
    }

    return null;
  }

  /// 解析评分
  double? _parseRating(XmlElement root) {
    // 尝试从 rating 元素获取
    final ratingStr = _getElementText(root, 'rating');
    if (ratingStr != null) {
      return double.tryParse(ratingStr);
    }

    // 尝试从 ratings/rating 获取
    try {
      final ratings = root.findElements('ratings').firstOrNull;
      if (ratings != null) {
        final rating = ratings.findElements('rating').firstOrNull;
        if (rating != null) {
          final value = rating.findElements('value').firstOrNull;
          if (value != null) {
            return double.tryParse(value.innerText.trim());
          }
        }
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'NFO ratings 节点解析失败');
    }

    return null;
  }

  /// 获取类型列表
  List<String>? _getGenres(XmlElement root) {
    try {
      final genres = root.findElements('genre').map((e) => e.innerText.trim()).toList();
      return genres.isNotEmpty ? genres : null;
    } on Exception catch (_) {
      return null;
    }
  }

  /// 获取国家/地区列表
  ///
  /// NFO 文件中可能包含多个 `<country>` 标签，例如：
  /// ```xml
  /// <country>United States</country>
  /// <country>United Kingdom</country>
  /// ```
  List<String>? _getCountries(XmlElement root) {
    try {
      final countries = root
          .findElements('country')
          .map((e) => e.innerText.trim())
          .where((c) => c.isNotEmpty)
          .toList();
      return countries.isNotEmpty ? countries : null;
    } on Exception catch (_) {
      return null;
    }
  }

  /// 获取演员列表
  List<String>? _getActors(XmlElement root) {
    try {
      final actors = <String>[];
      for (final actor in root.findElements('actor')) {
        final name = actor.findElements('name').firstOrNull?.innerText.trim();
        if (name != null && name.isNotEmpty) {
          actors.add(name);
        }
      }
      return actors.isNotEmpty ? actors : null;
    } on Exception catch (_) {
      return null;
    }
  }

  /// 解析 TMDB ID
  int? _parseTmdbId(XmlElement root) {
    // 从 tmdbid 元素获取
    final tmdbStr = _getElementText(root, 'tmdbid');
    if (tmdbStr != null) {
      return int.tryParse(tmdbStr);
    }

    // 从 uniqueid 获取
    try {
      for (final uniqueid in root.findElements('uniqueid')) {
        final type = uniqueid.getAttribute('type')?.toLowerCase();
        if (type == 'tmdb') {
          return int.tryParse(uniqueid.innerText.trim());
        }
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'NFO uniqueid TMDB 解析失败');
    }

    return null;
  }

  /// 解析电影系列名称
  ///
  /// 支持以下 NFO 格式：
  /// ```xml
  /// <set>
  ///   <name>漫威电影宇宙</name>
  ///   <overview>...</overview>
  /// </set>
  /// ```
  /// 或简化格式：
  /// ```xml
  /// <set>漫威电影宇宙</set>
  /// ```
  String? _parseSetName(XmlElement root) {
    try {
      final setElement = root.findElements('set').firstOrNull;
      if (setElement == null) return null;

      // 尝试获取嵌套的 <name> 元素
      final nameElement = setElement.findElements('name').firstOrNull;
      if (nameElement != null) {
        final name = nameElement.innerText.trim();
        return name.isNotEmpty ? name : null;
      }

      // 如果没有 <name>，直接使用 <set> 的文本（简化格式）
      final directText = setElement.innerText.trim();
      // 确保不是空的或只包含子元素的文本
      if (directText.isNotEmpty && !directText.contains('<')) {
        return directText;
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'NFO set 名称解析失败');
    }
    return null;
  }

  /// 解析电影系列描述
  String? _parseSetOverview(XmlElement root) {
    try {
      final setElement = root.findElements('set').firstOrNull;
      if (setElement == null) return null;

      final overviewElement = setElement.findElements('overview').firstOrNull;
      if (overviewElement != null) {
        final overview = overviewElement.innerText.trim();
        return overview.isNotEmpty ? overview : null;
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'NFO set overview 解析失败');
    }
    return null;
  }

  /// 解析电影系列 TMDB ID
  ///
  /// 从 NFO 的 `<set><tmdbcolid>...</tmdbcolid></set>` 标签中获取
  int? _parseSetTmdbId(XmlElement root) {
    try {
      final setElement = root.findElements('set').firstOrNull;
      if (setElement == null) return null;

      final tmdbColIdElement = setElement.findElements('tmdbcolid').firstOrNull;
      if (tmdbColIdElement != null) {
        final id = tmdbColIdElement.innerText.trim();
        return int.tryParse(id);
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'NFO set tmdbcolid 解析失败');
    }
    return null;
  }

  int? _parseInt(String? value) {
    if (value == null) return null;
    return int.tryParse(value);
  }

  /// 查找本地图片
  Future<Map<String, String?>> _findLocalImages(
    List<FileItem> files,
    String videoBaseName,
    NasFileSystem fileSystem,
    String videoDir,
  ) async {
    String? posterPath;
    String? fanartPath;
    String? thumbPath;

    for (final file in files) {
      if (file.isDirectory) continue;

      final fileName = file.name.toLowerCase();
      final baseName = _getBaseName(fileName);

      // 检查是否是图片文件
      var isImage = false;
      for (final ext in _imageExtensions) {
        if (fileName.endsWith(ext)) {
          isImage = true;
          break;
        }
      }
      if (!isImage) continue;

      // 检查是否是与视频同名的图片
      if (baseName == videoBaseName.toLowerCase()) {
        posterPath ??= file.path;
        continue;
      }

      // 检查海报模式
      if (posterPath == null) {
        for (final pattern in _posterPatterns) {
          if (baseName.contains(pattern) || baseName == pattern) {
            posterPath = file.path;
            break;
          }
        }
      }

      // 检查背景图模式
      if (fanartPath == null) {
        for (final pattern in _fanartPatterns) {
          if (baseName.contains(pattern) || baseName == pattern) {
            fanartPath = file.path;
            break;
          }
        }
      }

      // 检查缩略图模式
      if (thumbPath == null) {
        for (final pattern in _thumbPatterns) {
          if (baseName.contains(pattern) || baseName == pattern) {
            thumbPath = file.path;
            break;
          }
        }
      }
    }

    return {
      'poster': posterPath,
      'fanart': fanartPath,
      'thumb': thumbPath,
    };
  }

  /// 获取图片 URL（通过 NAS 适配器）
  Future<String?> getImageUrl({
    required NasFileSystem fileSystem,
    required String imagePath,
  }) async {
    try {
      // 尝试获取图片的下载 URL 或缩略图 URL
      return await fileSystem.getFileUrl(imagePath);
    } on Exception catch (e) {
      logger.w('NfoScraperService: 获取图片 URL 失败', e);
      return null;
    }
  }
}
