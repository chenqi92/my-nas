import 'dart:typed_data';
import 'package:my_nas/core/i18n/app_l10n.dart';

import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/media_server_adapters/base/media_server_entities.dart';
import 'package:my_nas/media_server_adapters/jellyfin/api/jellyfin_api.dart';
import 'package:my_nas/media_server_adapters/jellyfin/api/jellyfin_models.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// Jellyfin 虚拟文件系统
///
/// 将 Jellyfin 媒体库映射为文件系统结构，使其能够在文件浏览器中使用。
///
/// 路径映射：
/// ```
/// /                          -> 媒体库列表
/// /电影                       -> 电影库内容
/// /电影/钢铁侠 (2008).mkv     -> 电影项目（可播放）
/// /电视剧                     -> 剧集库内容
/// /电视剧/权力的游戏          -> 剧集详情
/// /电视剧/权力的游戏/第1季     -> 第一季
/// /电视剧/权力的游戏/第1季/S01E01 凛冬将至.mkv -> 剧集
/// ```
class JellyfinVirtualFileSystem implements NasFileSystem {
  JellyfinVirtualFileSystem({required JellyfinApi api}) : _api = api;

  final JellyfinApi _api;

  // 缓存媒体库列表
  List<JellyfinLibrary>? _librariesCache;

  // 路径到 itemId 的缓存
  final Map<String, String> _pathToIdCache = {};

  // itemId 到 item 的缓存
  final Map<String, JellyfinItem> _itemCache = {};

  @override
  Future<List<FileItem>> listDirectory(String path) async {
    logger.i('JellyfinVirtualFS: listDirectory, path=$path');

    final normalizedPath = _normalizePath(path);

    // 根目录：显示媒体库列表
    if (normalizedPath == '/') {
      return _listLibraries();
    }

    // 解析路径
    final itemId = await _resolvePathToId(normalizedPath);
    if (itemId == null) {
      logger.w('JellyfinVirtualFS: 路径无法解析, path=$path');
      return [];
    }

    // 获取 item 信息以确定类型
    final item = await _getItem(itemId);
    if (item == null) {
      return [];
    }

    // 根据类型决定如何列出内容
    return switch (item.type) {
      'Series' => _listSeriesContent(itemId),
      'Season' => _listSeasonEpisodes(item),
      'CollectionFolder' || 'Folder' => _listFolderContent(itemId),
      _ => _listFolderContent(itemId),
    };
  }

  @override
  Future<FileItem> getFileInfo(String path) async {
    logger.i('JellyfinVirtualFS: getFileInfo, path=$path');

    final normalizedPath = _normalizePath(path);

    if (normalizedPath == '/') {
      return const FileItem(
        name: '/',
        path: '/',
        isDirectory: true,
        size: 0,
      );
    }

    final itemId = await _resolvePathToId(normalizedPath);
    if (itemId == null) {
      throw Exception(appL10n.jellyfinVfsPathNotFound(path));
    }

    final item = await _getItem(itemId);
    if (item == null) {
      throw Exception(appL10n.jellyfinVfsItemNotFound(itemId));
    }

    return _itemToFileItem(item, normalizedPath);
  }

  @override
  Future<Stream<List<int>>> getFileStream(String path, {FileRange? range}) async {
    logger.i('JellyfinVirtualFS: getFileStream, path=$path');
    // 媒体服务器通常返回 URL 让播放器直接访问
    throw UnsupportedError(appL10n.jellyfinVfsUseGetFileUrl);
  }

  @override
  Future<Stream<List<int>>> getUrlStream(String url) async {
    // 媒体服务器通常返回 URL 让播放器直接访问
    throw UnsupportedError(appL10n.jellyfinVfsUseGetFileUrl);
  }

  @override
  Future<String> getFileUrl(String path, {Duration? expiry}) async {
    logger.i('JellyfinVirtualFS: getFileUrl, path=$path');

    final normalizedPath = _normalizePath(path);
    final itemId = await _resolvePathToId(normalizedPath);
    if (itemId == null) {
      throw Exception(appL10n.jellyfinVfsPathNotFound(path));
    }

    // 返回直接播放 URL
    return _api.getDirectStreamUrl(itemId);
  }

  @override
  Future<String?> getThumbnailUrl(String path, {ThumbnailSize? size}) async {
    final normalizedPath = _normalizePath(path);
    final itemId = await _resolvePathToId(normalizedPath);
    if (itemId == null) return null;

    final maxWidth = switch (size) {
      ThumbnailSize.small => 120,
      ThumbnailSize.medium => 240,
      ThumbnailSize.large => 480,
      ThumbnailSize.xlarge => 720,
      null => 240,
    };

    return _api.getImageUrl(
      itemId,
      MediaImageType.primary,
      maxWidth: maxWidth,
    );
  }

  @override
  Future<Uint8List?> getThumbnailData(String path, {ThumbnailSize? size}) async =>
      // 使用 URL 方式，不直接提供数据
      null;

  // === 不支持的写操作 ===

  @override
  Future<void> createDirectory(String path) async {
    throw UnsupportedError(appL10n.jellyfinVfsCreateDirNotSupported);
  }

  @override
  Future<void> delete(String path) async {
    throw UnsupportedError(appL10n.jellyfinVfsDeleteNotSupported);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    throw UnsupportedError(appL10n.jellyfinVfsRenameNotSupported);
  }

  @override
  Future<void> copy(String sourcePath, String destPath) async {
    throw UnsupportedError(appL10n.jellyfinVfsCopyNotSupported);
  }

  @override
  Future<void> move(String sourcePath, String destPath) async {
    throw UnsupportedError(appL10n.jellyfinVfsMoveNotSupported);
  }

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    throw UnsupportedError(appL10n.jellyfinVfsUploadNotSupported);
  }

  @override
  Future<void> writeFile(String remotePath, List<int> data) async {
    throw UnsupportedError(appL10n.jellyfinVfsWriteFileNotSupported);
  }

  @override
  Future<List<FileItem>> search(String query, {String? path}) async {
    logger.i('JellyfinVirtualFS: search, query=$query');
    final result = await _api.search(query);
    return result.items.map((e) => _itemToFileItem(e, '/${e.name}')).toList();
  }

  // === 私有方法 ===

  /// 规范化路径
  String _normalizePath(String path) {
    var normalized = path.replaceAll(r'\', '/');
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  /// 列出媒体库
  Future<List<FileItem>> _listLibraries() async {
    _librariesCache ??= await _api.getLibraries();

    return _librariesCache!.map((lib) {
      final path = '/${lib.name}';
      _pathToIdCache[path] = lib.id;
      return FileItem(
        name: lib.name,
        path: path,
        isDirectory: true,
        size: 0,
        thumbnailUrl: lib.primaryImageItemId != null
            ? _api.getImageUrl(
                lib.primaryImageItemId!,
                MediaImageType.primary,
                maxWidth: 240,
              )
            : null,
      );
    }).toList();
  }

  /// 列出文件夹内容
  Future<List<FileItem>> _listFolderContent(String parentId) async {
    final result = await _api.getItems(parentId: parentId);
    final parentPath = _idToPath(parentId) ?? '/';

    return result.items.map((item) {
      final itemPath = '$parentPath/${_sanitizeName(item.name)}';
      _pathToIdCache[itemPath] = item.id;
      _itemCache[item.id] = item;
      return _itemToFileItem(item, itemPath);
    }).toList();
  }

  /// 列出剧集内容（季列表）
  Future<List<FileItem>> _listSeriesContent(String seriesId) async {
    final result = await _api.getSeasons(seriesId);
    final parentPath = _idToPath(seriesId) ?? '/';

    return result.items.map((item) {
      final seasonName = item.name.isNotEmpty ? item.name : appL10n.jellyfinVfsSeasonNameDefault(item.indexNumber ?? 0);
      final itemPath = '$parentPath/${_sanitizeName(seasonName)}';
      _pathToIdCache[itemPath] = item.id;
      _itemCache[item.id] = item;
      return _itemToFileItem(item, itemPath);
    }).toList();
  }

  /// 列出季的集列表
  Future<List<FileItem>> _listSeasonEpisodes(JellyfinItem season) async {
    final seriesId = season.seriesId;
    if (seriesId == null) {
      return [];
    }

    final result = await _api.getEpisodes(seriesId, seasonId: season.id);
    final parentPath = _idToPath(season.id) ?? '/';

    return result.items.map((item) {
      // 构造剧集文件名：S01E01 凛冬将至.mkv
      final seasonNum =
          (item.parentIndexNumber ?? 1).toString().padLeft(2, '0');
      final episodeNum = (item.indexNumber ?? 1).toString().padLeft(2, '0');
      final fileName = 'S${seasonNum}E$episodeNum ${item.name}';
      final itemPath = '$parentPath/${_sanitizeName(fileName)}';

      _pathToIdCache[itemPath] = item.id;
      _itemCache[item.id] = item;
      return _itemToFileItem(item, itemPath);
    }).toList();
  }

  /// 解析路径到 itemId
  Future<String?> _resolvePathToId(String path) async {
    // 检查缓存
    if (_pathToIdCache.containsKey(path)) {
      return _pathToIdCache[path];
    }

    // 解析路径
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) {
      return null;
    }

    // 第一段是媒体库名称
    _librariesCache ??= await _api.getLibraries();
    final library = _librariesCache!.firstWhere(
      (lib) => lib.name == segments.first,
      orElse: () => const JellyfinLibrary(id: '', name: ''),
    );

    if (library.id.isEmpty) {
      return null;
    }

    if (segments.length == 1) {
      _pathToIdCache[path] = library.id;
      return library.id;
    }

    // 逐级查找
    var currentId = library.id;
    final currentPath = StringBuffer('/${segments.first}');

    for (var i = 1; i < segments.length; i++) {
      final segment = segments[i];
      final item = await _findItemInParent(currentId, segment);

      if (item == null) {
        return null;
      }

      currentId = item.id;
      currentPath.write('/$segment');
      _pathToIdCache[currentPath.toString()] = currentId;
      _itemCache[currentId] = item;
    }

    return currentId;
  }

  /// 在父项目中查找子项目
  Future<JellyfinItem?> _findItemInParent(String parentId, String name) async {
    // 先检查是否是剧集
    final parent = await _getItem(parentId);
    if (parent?.type == 'Series') {
      // 搜索季
      final seasons = await _api.getSeasons(parentId);
      for (final season in seasons.items) {
        final seasonName = season.name.isNotEmpty ? season.name : appL10n.jellyfinVfsSeasonNameDefault(season.indexNumber ?? 0);
        if (_sanitizeName(seasonName) == name) {
          return season;
        }
      }
      return null;
    }

    if (parent?.type == 'Season' && parent?.seriesId != null) {
      // 搜索集
      final episodes = await _api.getEpisodes(
        parent!.seriesId!,
        seasonId: parentId,
      );
      for (final ep in episodes.items) {
        final seasonNum =
            (ep.parentIndexNumber ?? 1).toString().padLeft(2, '0');
        final episodeNum = (ep.indexNumber ?? 1).toString().padLeft(2, '0');
        final fileName = 'S${seasonNum}E$episodeNum ${ep.name}';
        if (_sanitizeName(fileName) == name) {
          return ep;
        }
      }
      return null;
    }

    // 普通文件夹内容
    final result = await _api.getItems(parentId: parentId);
    for (final item in result.items) {
      if (_sanitizeName(item.name) == name) {
        return item;
      }
    }

    return null;
  }

  /// 获取项目信息
  Future<JellyfinItem?> _getItem(String itemId) async {
    if (_itemCache.containsKey(itemId)) {
      return _itemCache[itemId];
    }

    try {
      final item = await _api.getItem(itemId);
      _itemCache[itemId] = item;
      return item;
    } on Exception catch (e) {
      logger.w('JellyfinVirtualFS: 获取项目失败, itemId=$itemId', e);
      return null;
    }
  }

  /// 根据 id 反查路径（从缓存）
  String? _idToPath(String itemId) {
    for (final entry in _pathToIdCache.entries) {
      if (entry.value == itemId) {
        return entry.key;
      }
    }
    return null;
  }

  /// 清理名称（移除不安全字符）
  String _sanitizeName(String name) => name
        .replaceAll('/', '_')
        .replaceAll(r'\', '_')
        .replaceAll(':', '_')
        .replaceAll('*', '_')
        .replaceAll('?', '_')
        .replaceAll('"', '_')
        .replaceAll('<', '_')
        .replaceAll('>', '_')
        .replaceAll('|', '_');

  /// 将 JellyfinItem 转换为 FileItem
  FileItem _itemToFileItem(JellyfinItem item, String path) {
    final itemType = MediaItemType.fromJellyfinType(item.type);
    final isDirectory = itemType.isContainer;
    final isPlayable = itemType.isPlayable;

    // 确定文件扩展名
    String? ext;
    if (isPlayable) {
      // 从媒体源获取容器格式，或使用默认
      ext = '.mkv'; // 默认假设为 mkv
    }

    // 计算文件大小（从运行时长估算，或使用 0）
    var size = 0;
    if (item.runTimeTicks != null) {
      // 粗略估算：1小时约 5GB（对于1080p视频）
      size = (item.runTimeTicks! / 10000000 / 3600 * 5 * 1024 * 1024 * 1024)
          .round();
    }

    return FileItem(
      name: isPlayable ? '${item.name}$ext' : item.name,
      path: isPlayable ? '$path$ext' : path,
      isDirectory: isDirectory,
      size: size,
      modifiedTime: item.premiereDate,
      extension: ext,
      thumbnailUrl: item.hasPrimaryImage
          ? _api.getImageUrl(
              item.id,
              MediaImageType.primary,
              maxWidth: 240,
            )
          : null,
      mimeType: isPlayable ? 'video/x-matroska' : null,
    );
  }
}
