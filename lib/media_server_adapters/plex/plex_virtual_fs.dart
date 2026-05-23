import 'dart:typed_data';

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
      throw Exception('路径不存在: $path');
    }

    if (ratingKey.startsWith('library:')) {
      final libraryKey = ratingKey.substring(8);
      _librariesCache ??= await _api.getLibraries();
      final library = _librariesCache!.cast<PlexLibrary?>().firstWhere(
            (lib) => lib!.key == libraryKey,
            orElse: () => null,
          );
      if (library == null) {
        throw Exception('媒体库不存在: $libraryKey');
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
      throw Exception('项目不存在: $ratingKey');
    }

    return _itemToFileItem(item, normalizedPath);
  }

  @override
  Future<Stream<List<int>>> getFileStream(String path, {FileRange? range}) async {
    throw UnsupportedError('Plex 虚拟文件系统不支持直接读取流，请使用 getFileUrl');
  }

  @override
  Future<Stream<List<int>>> getUrlStream(String url) async {
    throw UnsupportedError('Plex 虚拟文件系统不支持 URL 流');
  }

  @override
  Future<String> getFileUrl(String path, {Duration? expiry}) async {
    final normalizedPath = _normalizePath(path);
    final ratingKey = await _resolvePathToKey(normalizedPath);
    if (ratingKey == null || ratingKey.startsWith('library:')) {
      throw Exception('无法获取文件 URL: $path');
    }

    final item = await _getItem(ratingKey);
    if (item == null || item.media == null || item.media!.isEmpty) {
      throw Exception('没有可用的媒体: $path');
    }

    final part = item.media!.first.parts?.first;
    if (part?.key == null) {
      throw Exception('没有可用的媒体部分: $path');
    }

    return _api.getPlayUrl(part!.key!);
  }

  @override
  Future<void> createDirectory(String path) async {
    throw UnsupportedError('Plex 虚拟文件系统不支持创建目录');
  }

  @override
  Future<void> delete(String path) async {
    throw UnsupportedError('Plex 虚拟文件系统不支持删除');
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    throw UnsupportedError('Plex 虚拟文件系统不支持重命名');
  }

  @override
  Future<void> copy(String sourcePath, String destPath) async {
    throw UnsupportedError('Plex 虚拟文件系统不支持复制');
  }

  @override
  Future<void> move(String sourcePath, String destPath) async {
    throw UnsupportedError('Plex 虚拟文件系统不支持移动');
  }

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    throw UnsupportedError('Plex 虚拟文件系统不支持上传');
  }

  @override
  Future<void> writeFile(String remotePath, List<int> data) async {
    throw UnsupportedError('Plex 虚拟文件系统不支持写入');
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

  FileItem _itemToFileItem(PlexMediaItem item, String path) => FileItem(
      name: item.isPlayable ? '${item.title}.mp4' : item.title,
      path: path,
      isDirectory: !item.isPlayable,
      size: 0,
      modifiedTime: item.originallyAvailableAt != null
          ? DateTime.tryParse(item.originallyAvailableAt!)
          : null,
    );

  String _stripExtension(String name) {
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex > 0) {
      return name.substring(0, dotIndex);
    }
    return name;
  }
}
