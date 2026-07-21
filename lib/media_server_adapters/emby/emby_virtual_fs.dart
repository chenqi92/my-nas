import 'dart:typed_data';
import 'package:my_nas/core/i18n/app_l10n.dart';

import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/media_server_adapters/emby/api/emby_api.dart';
import 'package:my_nas/media_server_adapters/jellyfin/api/jellyfin_models.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// Emby 虚拟文件系统
///
/// 将 Emby 媒体库映射为文件系统结构，用于文件浏览器兼容
class EmbyVirtualFileSystem implements NasFileSystem {
  EmbyVirtualFileSystem({required EmbyApi api, required String sourceId})
    : _api = api,
      _sourceId = sourceId;

  final EmbyApi _api;
  // ignore: unused_field
  final String _sourceId;

  // 缓存
  List<JellyfinLibrary>? _librariesCache;
  final Map<String, String> _pathToIdCache = {};
  final Map<String, JellyfinItem> _itemCache = {};

  @override
  bool get supportsWriteOperations => false;

  @override
  bool get supportsServerSideCopy => false;

  @override
  bool get supportsDirectFileUrl => true;

  @override
  Future<List<FileItem>> listDirectory(String path) async {
    logger.d('EmbyVirtualFS: listDirectory, path=$path');

    final normalizedPath = _normalizePath(path);

    if (normalizedPath == '/') {
      return _listLibraries();
    }

    final itemId = await _resolvePathToId(normalizedPath);
    if (itemId == null) {
      return [];
    }

    return _listFolderContent(itemId, parentPath: normalizedPath);
  }

  @override
  Future<FileItem> getFileInfo(String path) async {
    final normalizedPath = _normalizePath(path);

    if (normalizedPath == '/') {
      return const FileItem(name: '/', path: '/', isDirectory: true, size: 0);
    }

    final itemId = await _resolvePathToId(normalizedPath);
    if (itemId == null) {
      throw Exception(appL10n.embyVfsPathNotFound(path));
    }

    final item = await _getItem(itemId);
    if (item == null) {
      throw Exception(appL10n.embyVfsItemNotFound(itemId));
    }

    return _itemToFileItem(item, normalizedPath);
  }

  @override
  Future<Stream<List<int>>> getFileStream(
    String path, {
    FileRange? range,
  }) async {
    throw UnsupportedError(appL10n.embyVfsUnsupportedStreamRead);
  }

  @override
  Future<Stream<List<int>>> getUrlStream(String url) async {
    throw UnsupportedError(appL10n.embyVfsUnsupportedUrlStream);
  }

  @override
  Future<String> getFileUrl(String path, {Duration? expiry}) async {
    final normalizedPath = _normalizePath(path);
    final itemId = await _resolvePathToId(normalizedPath);
    if (itemId == null) {
      throw Exception(appL10n.embyVfsFailedResolveePath(path));
    }
    final item = await _getItem(itemId);
    return _api.getDirectStreamUrl(
      itemId,
      isAudio: item?.type?.toLowerCase() == 'audio',
    );
  }

  @override
  Future<void> createDirectory(String path) async {
    throw UnsupportedError(appL10n.embyVfsUnsupportedCreateDirectory);
  }

  @override
  Future<void> delete(String path) async {
    throw UnsupportedError(appL10n.embyVfsUnsupportedDelete);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    throw UnsupportedError(appL10n.embyVfsUnsupportedRename);
  }

  @override
  Future<void> copy(String sourcePath, String destPath) async {
    throw UnsupportedError(appL10n.embyVfsUnsupportedCopy);
  }

  @override
  Future<void> move(String sourcePath, String destPath) async {
    throw UnsupportedError(appL10n.embyVfsUnsupportedMove);
  }

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    throw UnsupportedError(appL10n.embyVfsUnsupportedUpload);
  }

  @override
  Future<void> writeFile(String remotePath, List<int> data) async {
    throw UnsupportedError(appL10n.embyVfsUnsupportedWrite);
  }

  @override
  Future<List<FileItem>> search(String query, {String? path}) async {
    final result = await _api.search(query);
    return result.items.map((item) {
      final itemPath = '/${item.name}';
      return _itemToFileItem(item, itemPath);
    }).toList();
  }

  @override
  Future<String?> getThumbnailUrl(String path, {ThumbnailSize? size}) async {
    final normalizedPath = _normalizePath(path);
    final itemId = await _resolvePathToId(normalizedPath);
    if (itemId == null) return null;

    final maxWidth = switch (size) {
      ThumbnailSize.small => 150,
      ThumbnailSize.medium => 300,
      ThumbnailSize.large => 600,
      ThumbnailSize.xlarge => 900,
      null => 300,
    };

    return _api.getImageUrl(itemId, 'Primary', maxWidth: maxWidth);
  }

  @override
  Future<Uint8List?> getThumbnailData(
    String path, {
    ThumbnailSize? size,
  }) async => null;

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

    return _librariesCache!.map((lib) {
      final path = '/${lib.name}';
      _pathToIdCache[path] = lib.id;

      return FileItem(name: lib.name, path: path, isDirectory: true, size: 0);
    }).toList();
  }

  Future<List<FileItem>> _listFolderContent(
    String parentId, {
    String parentPath = '',
  }) async {
    final result = await _api.getItems(parentId: parentId, limit: 1000);

    final items = <FileItem>[];
    for (final item in result.items) {
      final itemPath = _buildItemPath(item, parentPath);
      _pathToIdCache[itemPath] = item.id;
      _itemCache[item.id] = item;
      items.add(_itemToFileItem(item, itemPath));
    }

    return items;
  }

  Future<String?> _resolvePathToId(String path) async {
    if (_pathToIdCache.containsKey(path)) {
      return _pathToIdCache[path];
    }

    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return null;

    // 确保库缓存已加载
    _librariesCache ??= await _api.getLibraries();

    // 查找库
    final libraryName = parts[0];
    final library = _librariesCache!.cast<JellyfinLibrary?>().firstWhere(
      (lib) => lib!.name == libraryName,
      orElse: () => null,
    );
    if (library == null) return null;

    if (parts.length == 1) {
      _pathToIdCache[path] = library.id;
      return library.id;
    }

    // 逐级解析
    var currentId = library.id;
    for (var i = 1; i < parts.length; i++) {
      final name = _stripExtension(parts[i]);
      final result = await _api.getItems(parentId: currentId, limit: 1000);
      final item = result.items.cast<JellyfinItem?>().firstWhere(
        (item) => item!.name == name,
        orElse: () => null,
      );
      if (item == null) return null;
      currentId = item.id;
      _itemCache[item.id] = item;
    }

    _pathToIdCache[path] = currentId;
    return currentId;
  }

  Future<JellyfinItem?> _getItem(String itemId) async {
    if (_itemCache.containsKey(itemId)) {
      return _itemCache[itemId];
    }
    final item = await _api.getItem(itemId);
    _itemCache[itemId] = item;
    return item;
  }

  /// 在父路径下构建条目路径，保留层级以避免同名条目路径冲突。
  String _buildItemPath(JellyfinItem item, String parentPath) {
    if (parentPath.isEmpty || parentPath == '/') {
      return '/${item.name}';
    }
    return '$parentPath/${item.name}';
  }

  FileItem _itemToFileItem(JellyfinItem item, String path) {
    final isPlayable =
        item.type == 'Movie' || item.type == 'Episode' || item.type == 'Audio';

    // 从 Emby item 的真实媒体源读取容器格式与文件大小（参考 emby_adapter
    // source.container / source.size 的取法）。getItems/getItem 默认不返回
    // MediaSources，缺失时回退默认扩展名与 0 字节。
    final source = _firstMediaSource(item);
    final container = (source?['Container'] as String?)?.trim();
    final extension = (container != null && container.isNotEmpty)
        ? container
        : 'mp4';
    final size = (source?['Size'] as num?)?.toInt() ?? 0;

    return FileItem(
      name: isPlayable ? '${item.name}.$extension' : item.name,
      path: path,
      isDirectory: !isPlayable,
      size: isPlayable ? size : 0,
      extension: isPlayable ? extension : null,
      modifiedTime: item.premiereDate,
    );
  }

  /// 取 item 的首个媒体源原始 JSON（JellyfinItem.mediaSources 为原始 Map 列表）。
  Map<String, dynamic>? _firstMediaSource(JellyfinItem item) {
    final sources = item.mediaSources;
    if (sources == null || sources.isEmpty) return null;
    final first = sources.first;
    return first is Map<String, dynamic> ? first : null;
  }

  String _stripExtension(String name) {
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex > 0) {
      return name.substring(0, dotIndex);
    }
    return name;
  }
}
