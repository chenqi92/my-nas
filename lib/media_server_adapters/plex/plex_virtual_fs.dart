import 'dart:typed_data';

import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/media_server_adapters/plex/api/plex_api.dart';
import 'package:my_nas/media_server_adapters/plex/api/plex_models.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// Plex 虚拟文件系统
///
/// 将 Plex 媒体库映射为文件系统结构，用于文件浏览器兼容
class PlexVirtualFileSystem implements NasFileSystem {
  PlexVirtualFileSystem({
    required PlexApi api,
    required String sourceId,
  })  : _api = api,
        _sourceId = sourceId;

  final PlexApi _api;
  // ignore: unused_field
  final String _sourceId;

  // 缓存
  List<PlexLibrary>? _librariesCache;
  final Map<String, String> _pathToKeyCache = {};
  final Map<String, PlexMediaItem> _itemCache = {};

  @override
  Future<List<FileItem>> listDirectory(String path) async {
    logger.d('PlexVirtualFS: listDirectory, path=$path');

    final normalizedPath = _normalizePath(path);

    if (normalizedPath == '/') {
      return _listLibraries();
    }

    final ratingKey = await _resolvePathToKey(normalizedPath);
    if (ratingKey == null) {
      return [];
    }

    if (ratingKey.startsWith('library:')) {
      final libraryKey = ratingKey.substring(8);
      return _listLibraryContent(libraryKey);
    }

    return _listItemChildren(ratingKey);
  }

  @override
  Future<FileItem> getFileInfo(String path) async {
    final normalizedPath = _normalizePath(path);

    if (normalizedPath == '/') {
      return const FileItem(
        name: '/',
        path: '/',
        isDirectory: true,
        size: 0,
      );
    }

    final ratingKey = await _resolvePathToKey(normalizedPath);
    if (ratingKey == null) {
      throw Exception(appL10n.plexVfsPathNotExist(path));
    }

    if (ratingKey.startsWith('library:')) {
      final libraryKey = ratingKey.substring(8);
      _librariesCache ??= await _api.getLibraries();
      final library = _librariesCache!.cast<PlexLibrary?>().firstWhere(
            (lib) => lib!.key == libraryKey,
            orElse: () => null,
          );
      if (library == null) {
        throw Exception(appL10n.plexVfsLibraryNotExist(libraryKey));
      }
      return FileItem(
        name: library.title,
        path: normalizedPath,
        isDirectory: true,
        size: 0,
      );
    }

    final item = await _getItem(ratingKey);
    if (item == null) {
      throw Exception(appL10n.plexVfsItemNotExist(ratingKey));
    }

    return _itemToFileItem(item, normalizedPath);
  }

  @override
  Future<Stream<List<int>>> getFileStream(String path, {FileRange? range}) async {
    throw UnsupportedError(appL10n.plexVfsDirectReadStreamNotSupported);
  }

  @override
  Future<Stream<List<int>>> getUrlStream(String url) async {
    throw UnsupportedError(appL10n.plexVfsUrlStreamNotSupported);
  }

  @override
  Future<String> getFileUrl(String path, {Duration? expiry}) async {
    final normalizedPath = _normalizePath(path);
    final ratingKey = await _resolvePathToKey(normalizedPath);
    if (ratingKey == null || ratingKey.startsWith('library:')) {
      throw Exception(appL10n.plexVfsGetFileUrlFailed(path));
    }

    final item = await _getItem(ratingKey);
    if (item == null || item.media == null || item.media!.isEmpty) {
      throw Exception(appL10n.plexVfsNoAvailableMedia(path));
    }

    final part = item.media!.first.parts?.first;
    if (part?.key == null) {
      throw Exception(appL10n.plexVfsNoMediaPart(path));
    }

    return _api.getPlayUrl(part!.key!);
  }

  @override
  Future<void> createDirectory(String path) async {
    throw UnsupportedError(appL10n.plexVfsCreateDirectoryNotSupported);
  }

  @override
  Future<void> delete(String path) async {
    throw UnsupportedError(appL10n.plexVfsDeleteNotSupported);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    throw UnsupportedError(appL10n.plexVfsRenameNotSupported);
  }

  @override
  Future<void> copy(String sourcePath, String destPath) async {
    throw UnsupportedError(appL10n.plexVfsCopyNotSupported);
  }

  @override
  Future<void> move(String sourcePath, String destPath) async {
    throw UnsupportedError(appL10n.plexVfsMoveNotSupported);
  }

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    throw UnsupportedError(appL10n.plexVfsUploadNotSupported);
  }

  @override
  Future<void> writeFile(String remotePath, List<int> data) async {
    throw UnsupportedError(appL10n.plexVfsWriteNotSupported);
  }

  @override
  Future<List<FileItem>> search(String query, {String? path}) async {
    final result = await _api.search(query);
    return result.items.map((item) {
      final itemPath = '/${item.title}';
      return _itemToFileItem(item, itemPath);
    }).toList();
  }

  @override
  Future<String?> getThumbnailUrl(String path, {ThumbnailSize? size}) async {
    final normalizedPath = _normalizePath(path);
    final ratingKey = await _resolvePathToKey(normalizedPath);
    if (ratingKey == null || ratingKey.startsWith('library:')) {
      return null;
    }

    final item = await _getItem(ratingKey);
    if (item?.thumb == null) return null;

    final maxWidth = switch (size) {
      ThumbnailSize.small => 150,
      ThumbnailSize.medium => 300,
      ThumbnailSize.large => 600,
      ThumbnailSize.xlarge => 900,
      null => 300,
    };

    return _api.getImageUrl(item!.thumb!, width: maxWidth);
  }

  @override
  Future<Uint8List?> getThumbnailData(String path, {ThumbnailSize? size}) async => null;

  // === 私有方法 ===

  String _normalizePath(String path) {
    var normalized = path.replaceAll(r'\', '/');
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }
    while (normalized.endsWith('/') && normalized.length > 1) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  Future<List<FileItem>> _listLibraries() async {
    _librariesCache ??= await _api.getLibraries();

    return _librariesCache!.where((lib) => lib.isVideo).map((lib) {
      final path = '/${lib.title}';
      _pathToKeyCache[path] = 'library:${lib.key}';

      return FileItem(
        name: lib.title,
        path: path,
        isDirectory: true,
        size: 0,
      );
    }).toList();
  }

  Future<List<FileItem>> _listLibraryContent(String libraryKey) async {
    final result = await _api.getLibraryContents(libraryKey, size: 1000);

    final items = <FileItem>[];
    for (final item in result.items) {
      final itemPath = '/${item.title}';
      _pathToKeyCache[itemPath] = item.ratingKey;
      _itemCache[item.ratingKey] = item;
      items.add(_itemToFileItem(item, itemPath));
    }

    return items;
  }

  Future<List<FileItem>> _listItemChildren(String ratingKey) async {
    final result = await _api.getItemChildren(ratingKey);

    final items = <FileItem>[];
    for (final item in result.items) {
      final itemPath = '/${item.title}';
      _pathToKeyCache[itemPath] = item.ratingKey;
      _itemCache[item.ratingKey] = item;
      items.add(_itemToFileItem(item, itemPath));
    }

    return items;
  }

  Future<String?> _resolvePathToKey(String path) async {
    if (_pathToKeyCache.containsKey(path)) {
      return _pathToKeyCache[path];
    }

    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return null;

    _librariesCache ??= await _api.getLibraries();

    final libraryName = parts[0];
    final library = _librariesCache!.cast<PlexLibrary?>().firstWhere(
          (lib) => lib!.title == libraryName,
          orElse: () => null,
        );
    if (library == null) return null;

    if (parts.length == 1) {
      final key = 'library:${library.key}';
      _pathToKeyCache[path] = key;
      return key;
    }

    // 逐级解析
    var result = await _api.getLibraryContents(library.key);
    String? currentKey;

    for (var i = 1; i < parts.length; i++) {
      final name = _stripExtension(parts[i]);
      final item = result.items.cast<PlexMediaItem?>().firstWhere(
            (item) => item!.title == name,
            orElse: () => null,
          );
      if (item == null) return null;
      currentKey = item.ratingKey;
      _itemCache[item.ratingKey] = item;

      if (i < parts.length - 1) {
        result = await _api.getItemChildren(currentKey);
      }
    }

    if (currentKey != null) {
      _pathToKeyCache[path] = currentKey;
    }
    return currentKey;
  }

  Future<PlexMediaItem?> _getItem(String ratingKey) async {
    if (_itemCache.containsKey(ratingKey)) {
      return _itemCache[ratingKey];
    }
    final item = await _api.getItem(ratingKey);
    if (item != null) {
      _itemCache[ratingKey] = item;
    }
    return item;
  }

  FileItem _itemToFileItem(PlexMediaItem item, String path) {
    final media = (item.media != null && item.media!.isNotEmpty)
        ? item.media!.first
        : null;
    final part = (media?.parts != null && media!.parts!.isNotEmpty)
        ? media.parts!.first
        : null;

    final name = item.isPlayable
        ? '${item.title}.${_resolveExtension(media, part)}'
        : item.title;

    return FileItem(
      name: name,
      path: path,
      isDirectory: !item.isPlayable,
      size: part?.size ?? 0,
      modifiedTime: item.originallyAvailableAt != null
          ? DateTime.tryParse(item.originallyAvailableAt!)
          : null,
    );
  }

  /// 根据 Plex 容器信息推导可播放项扩展名，缺失时回退默认 mp4
  String _resolveExtension(PlexMedia? media, PlexPart? part) {
    final container = part?.container ?? media?.container;
    if (container != null && container.isNotEmpty) {
      return container;
    }
    return 'mp4';
  }

  String _stripExtension(String name) {
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex > 0) {
      return name.substring(0, dotIndex);
    }
    return name;
  }
}
