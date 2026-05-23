import 'dart:io';
import 'dart:typed_data';

import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart' as fs;
import 'package:photo_manager/photo_manager.dart' as pm;

/// URL 编码辅助方法（仅编码斜杠和百分号）
String _encodeId(String id) => id.replaceAll('%', '%25').replaceAll('/', '%2F');

/// URL 解码辅助方法
String _decodeId(String encoded) =>
    encoded.replaceAll('%2F', '/').replaceAll('%25', '%');

/// 移动端相册文件系统
///
/// 将系统相册映射为虚拟文件系统结构：
/// - /albums/           - 按相册分组
/// - /albums/{name}/    - 具体相册内容
/// - /all/              - 所有照片和视频
///
/// 路径格式：
/// - gallery://albums/{albumId}/{assetId}
/// - gallery://all/{assetId}
class MobileGalleryFileSystem implements NasFileSystem {
  MobileGalleryFileSystem();

  List<pm.AssetPathEntity>? _cachedAlbums;
  final Map<String, pm.AssetEntity> _assetCache = {};

  /// 请求相册访问权限
  Future<bool> requestPermission() async {
    // ignore: avoid_print
    print('🔵 MobileGalleryFileSystem: 请求相册权限...');
    logger.i('MobileGalleryFileSystem: 请求相册权限...');

    final permission = await pm.PhotoManager.requestPermissionExtend();
    // ignore: avoid_print
    print('🔵 MobileGalleryFileSystem: 权限请求结果 - $permission, isAuth=${permission.isAuth}');
    logger.i('MobileGalleryFileSystem: 权限请求结果 - $permission');

    if (permission.isAuth) {
      // 权限获取成功，清除缓存以便重新加载相册
      _cachedAlbums = null;
      logger.i('MobileGalleryFileSystem: 完全访问权限已获取');
      return true;
    }
    if (permission == pm.PermissionState.limited) {
      // iOS 14+ 限制访问（用户选择了部分照片）
      _cachedAlbums = null;
      logger.i('MobileGalleryFileSystem: 限制访问权限已获取（iOS 14+ 选择部分照片）');
      return true;
    }
    logger.w('MobileGalleryFileSystem: 权限被拒绝 - $permission');
    return false;
  }

  /// 获取所有相册
  Future<List<pm.AssetPathEntity>> _getAlbums() async {
    // ignore: avoid_print
    print('🔵 MobileGalleryFileSystem: _getAlbums() 被调用, _cachedAlbums=${_cachedAlbums?.length}');

    if (_cachedAlbums != null) {
      // ignore: avoid_print
      print('🔵 MobileGalleryFileSystem: 使用缓存相册列表，数量: ${_cachedAlbums!.length}');
      logger.d('MobileGalleryFileSystem: 使用缓存相册列表，数量: ${_cachedAlbums!.length}');
      return _cachedAlbums!;
    }

    // ignore: avoid_print
    print('🔵 MobileGalleryFileSystem: 开始调用 PhotoManager.getAssetPathList...');
    logger.i('MobileGalleryFileSystem: 开始获取相册列表...');

    try {
      _cachedAlbums = await pm.PhotoManager.getAssetPathList(
        type: pm.RequestType.common, // 照片和视频
        hasAll: true,
        onlyAll: false,
      );

      // ignore: avoid_print
      print('🔵 MobileGalleryFileSystem: getAssetPathList 返回 ${_cachedAlbums!.length} 个相册');
      logger.i('MobileGalleryFileSystem: 获取到 ${_cachedAlbums!.length} 个相册');

      // 打印每个相册的详细信息用于调试
      for (final album in _cachedAlbums!) {
        final count = await album.assetCountAsync;
        // ignore: avoid_print
        print('🔵   - ${album.name} (id: ${album.id}, isAll: ${album.isAll}): $count 个资源');
        logger.d('  - ${album.name} (id: ${album.id}, isAll: ${album.isAll}): $count 个资源');
      }

      if (_cachedAlbums!.isEmpty) {
        // ignore: avoid_print
        print('🔵 MobileGalleryFileSystem: ⚠️ 相册列表为空！');
        logger.w('MobileGalleryFileSystem: 相册列表为空，可能没有权限或没有媒体文件');
      }

      return _cachedAlbums!;
    } on Exception catch (e, st) {
      // ignore: avoid_print
      print('🔵 MobileGalleryFileSystem: ❌ 获取相册列表失败: $e');
      logger.e('MobileGalleryFileSystem: 获取相册列表失败', e, st);
      _cachedAlbums = [];
      return _cachedAlbums!;
    }
  }

  /// 刷新相册缓存
  Future<void> refreshCache() async {
    _cachedAlbums = null;
    _assetCache.clear();
  }

  @override
  Future<List<FileItem>> listDirectory(String path) async {
    // ignore: avoid_print
    print('🔵 MobileGalleryFileSystem: listDirectory("$path")');
    logger.d('MobileGalleryFileSystem: listDirectory - $path');

    // 根目录
    if (path == '/' || path.isEmpty) {
      // ignore: avoid_print
      print('🔵 MobileGalleryFileSystem: → 调用 _listRoot()');
      return _listRoot();
    }

    // 相册列表
    if (path == '/albums' || path == '/albums/') {
      // ignore: avoid_print
      print('🔵 MobileGalleryFileSystem: → 调用 _listAlbums()');
      return _listAlbums();
    }

    // 所有照片
    if (path == '/all' || path == '/all/') {
      // ignore: avoid_print
      print('🔵 MobileGalleryFileSystem: → 调用 _listAllAssets()');
      return _listAllAssets();
    }

    // 具体相册内容
    // 路径格式: /albums/{encodedAlbumId} 或 /albums/{encodedAlbumId}/{encodedAssetId}
    if (path.startsWith('/albums/')) {
      final remaining = path.replaceFirst('/albums/', '');
      final segments = remaining.split('/');
      // 第一段是编码后的 album ID，需要解码
      final albumId = _decodeId(segments.first);

      // 如果路径包含多个段（如 /albums/{albumId}/{assetId}），
      // 说明是访问具体资源，不是目录，返回空列表
      if (segments.length > 1 && segments[1].isNotEmpty) {
        logger.d('MobileGalleryFileSystem: 跳过资源路径 - $path');
        return [];
      }

      // ignore: avoid_print
      print('🔵 MobileGalleryFileSystem: → 调用 _listAlbumAssets("$albumId")');
      return _listAlbumAssets(albumId);
    }

    // ignore: avoid_print
    print('🔵 MobileGalleryFileSystem: 路径不匹配任何规则，返回空列表');
    return [];
  }

  /// 列出根目录
  ///
  /// 只返回 /albums，不返回 /all，避免同一批照片被扫描两次
  /// （/albums 中的 isAll=true 相册已经包含所有照片）
  Future<List<FileItem>> _listRoot() async => [
    const FileItem(
      name: 'albums',
      path: '/albums',
      isDirectory: true,
      size: 0,
    ),
  ];

  /// 列出所有相册
  ///
  /// 注意：只返回 isAll=true 的相册（"所有照片"），避免重复扫描。
  /// iOS 的智能相册（Screenshots、Favorites 等）中的照片都已包含在 isAll 相册中。
  Future<List<FileItem>> _listAlbums() async {
    // ignore: avoid_print
    print('🔵 MobileGalleryFileSystem: _listAlbums() 开始');
    logger.i('MobileGalleryFileSystem: _listAlbums 开始');
    final albums = await _getAlbums();
    // ignore: avoid_print
    print('🔵 MobileGalleryFileSystem: _listAlbums() 获取到 ${albums.length} 个相册');
    logger.i('MobileGalleryFileSystem: _listAlbums 获取到 ${albums.length} 个相册');

    final items = <FileItem>[];

    for (final album in albums) {
      // 只返回 isAll=true 的相册（"所有照片/Recents"），避免重复
      // 智能相册（Screenshots、Favorites 等）中的照片都已包含在 isAll 相册中
      if (!album.isAll) {
        continue;
      }

      final count = await album.assetCountAsync;
      // 对 album ID 进行编码，避免包含斜杠导致路径解析错误
      final encodedId = _encodeId(album.id);
      // ignore: avoid_print
      print('🔵 MobileGalleryFileSystem: 相册 "${album.name}" (id: ${album.id}, isAll: ${album.isAll}) 有 $count 个资源');
      logger.d('MobileGalleryFileSystem: 相册 "${album.name}" (id: ${album.id}) 有 $count 个资源');
      items.add(FileItem(
        name: album.name,
        path: '/albums/$encodedId',
        isDirectory: true,
        size: count,
      ));
    }

    // ignore: avoid_print
    print('🔵 MobileGalleryFileSystem: _listAlbums() 返回 ${items.length} 个相册（仅 isAll=true）');
    logger.i('MobileGalleryFileSystem: _listAlbums 返回 ${items.length} 个相册');
    return items;
  }

  /// 列出所有资源
  Future<List<FileItem>> _listAllAssets() async {
    final albums = await _getAlbums();

    // 找到 "所有照片" 相册
    final allAlbum = albums.firstWhere(
      (a) => a.isAll,
      orElse: () => albums.first,
    );

    return _listAlbumAssets(allAlbum.id);
  }

  /// 列出相册内资源
  ///
  /// 优化策略：
  /// 1. 分批加载资源，避免一次性加载导致内存问题
  /// 2. 不在列表时获取文件信息，延迟到需要时再获取
  /// 3. Live Photo 视频路径延迟加载
  Future<List<FileItem>> _listAlbumAssets(String albumId) async {
    // ignore: avoid_print
    print('🔵 MobileGalleryFileSystem: _listAlbumAssets("$albumId") 开始');
    logger.d('MobileGalleryFileSystem: _listAlbumAssets - albumId: $albumId');

    final albums = await _getAlbums();
    // ignore: avoid_print
    print('🔵 MobileGalleryFileSystem: _listAlbumAssets 获取到 ${albums.length} 个相册');
    logger.d('MobileGalleryFileSystem: 可用相册数量: ${albums.length}');

    if (albums.isEmpty) {
      // ignore: avoid_print
      print('🔵 MobileGalleryFileSystem: ⚠️ 相册列表为空，返回空列表');
      logger.w('MobileGalleryFileSystem: 相册列表为空，可能没有权限或没有照片');
      return [];
    }

    final album = albums.firstWhere(
      (a) => a.id == albumId,
      orElse: () {
        // ignore: avoid_print
        print('🔵 MobileGalleryFileSystem: ❌ 找不到相册 $albumId');
        logger.w('MobileGalleryFileSystem: 找不到相册 $albumId');
        logger.d('可用相册 ID: ${albums.map((a) => a.id).join(', ')}');
        throw Exception('Album not found: $albumId');
      },
    );

    // ignore: avoid_print
    print('🔵 MobileGalleryFileSystem: ✓ 找到相册 "${album.name}" (id: ${album.id})');

    final count = await album.assetCountAsync;
    // ignore: avoid_print
    print('🔵 MobileGalleryFileSystem: 相册 "${album.name}" 共有 $count 个资源');
    logger.i('MobileGalleryFileSystem: 相册 "${album.name}" 共有 $count 个资源');

    // 对 album ID 进行编码
    final encodedAlbumId = _encodeId(albumId);

    final items = <FileItem>[];

    // 分批加载资源，每批 100 个，避免一次性加载导致内存问题
    const batchSize = 100;
    for (var start = 0; start < count; start += batchSize) {
      final end = (start + batchSize > count) ? count : start + batchSize;
      final assets = await album.getAssetListRange(start: start, end: end);

      for (final asset in assets) {
        _assetCache[asset.id] = asset;

        // 从 asset.type 推断 mimeType（photo_manager 的 mimeType 属性经常为 null）
        // AssetType: image=1, video=2, audio=3, other=0
        var mimeType = asset.mimeType;
        String? extension;

        // 优先从文件名获取扩展名
        final title = asset.title;
        if (title != null && title.contains('.')) {
          extension = title.split('.').last.toLowerCase();
        }

        // 如果 mimeType 为 null，根据 asset.type 推断
        if (mimeType == null) {
          if (asset.type == pm.AssetType.image) {
            // iOS 默认使用 HEIC 格式
            mimeType = extension != null ? 'image/$extension' : 'image/heic';
            extension ??= 'heic';
          } else if (asset.type == pm.AssetType.video) {
            mimeType = extension != null ? 'video/$extension' : 'video/mp4';
            extension ??= 'mp4';
          }
        } else if (extension == null) {
          // 从 mimeType 推断扩展名，如 image/heic → heic
          final parts = mimeType.split('/');
          if (parts.length == 2) {
            extension = parts[1].toLowerCase();
          }
        }

        // 检测是否为 Live Photo（iOS 实况照片）
        // Live Photo 的 subtype 包含 PHAssetMediaSubtypePhotoLive (1 << 3 = 8)
        final isLivePhoto = Platform.isIOS && (asset.subtype & 8) != 0;

        // 对 asset ID 进行编码
        final encodedAssetId = _encodeId(asset.id);

        // 使用 asset 的元数据估算文件大小，不调用 file.lengthSync()
        // width * height * 4 bytes (RGBA) / 10 作为粗略估计
        // 实际大小会在需要时通过 getFileInfo 获取
        final estimatedSize = asset.width * asset.height * 4 ~/ 10;

        items.add(FileItem(
          name: title ?? asset.id,
          path: '/albums/$encodedAlbumId/$encodedAssetId',
          isDirectory: false,
          size: estimatedSize,
          modifiedTime: asset.modifiedDateTime,
          createdTime: asset.createDateTime,
          extension: extension,
          mimeType: mimeType,
          isLivePhoto: isLivePhoto,
          // Live Photo 视频路径延迟加载，不在列表时获取
          livePhotoVideoPath: null,
        ));
      }

      // 每批处理后让出主线程，避免 UI 卡顿
      await Future<void>.delayed(Duration.zero);
    }

    // ignore: avoid_print
    print('🔵 MobileGalleryFileSystem: _listAlbumAssets 返回 ${items.length} 个资源');
    return items;
  }

  @override
  Future<FileItem> getFileInfo(String path) async {
    // 解码 asset ID（路径最后一段是编码后的 ID）
    final assetId = _decodeId(path.split('/').last);
    var asset = _assetCache[assetId];

    // 如果缓存中没有，尝试从系统获取
    if (asset == null) {
      asset = await pm.AssetEntity.fromId(assetId);
      if (asset == null) {
        throw Exception('Asset not found: $assetId');
      }
      _assetCache[assetId] = asset;
    }

    final file = await asset.file;

    // 提取扩展名：优先从文件名获取，否则从 mimeType 推断
    String? extension;
    final title = asset.title;
    if (title != null && title.contains('.')) {
      extension = title.split('.').last.toLowerCase();
    } else if (asset.mimeType != null) {
      final parts = asset.mimeType!.split('/');
      if (parts.length == 2) {
        extension = parts[1].toLowerCase();
      }
    }

    // 检测是否为 Live Photo
    final isLivePhoto = Platform.isIOS && (asset.subtype & 8) != 0;

    // 获取 Live Photo 的视频路径
    String? livePhotoVideoPath;
    if (isLivePhoto) {
      final videoFile = await asset.fileWithSubtype;
      livePhotoVideoPath = videoFile?.path;
    }

    return FileItem(
      name: asset.title ?? asset.id,
      path: path,
      isDirectory: false,
      size: file?.lengthSync() ?? 0,
      modifiedTime: asset.modifiedDateTime,
      createdTime: asset.createDateTime,
      extension: extension,
      mimeType: asset.mimeType,
      isLivePhoto: isLivePhoto,
      livePhotoVideoPath: livePhotoVideoPath,
    );
  }

  /// 获取 Live Photo 的视频文件
  ///
  /// 返回 Live Photo 关联的视频文件路径，用于播放实况效果
  Future<File?> getLivePhotoVideoFile(String assetId) async {
    final asset = _assetCache[assetId];
    if (asset == null) return null;

    // 检测是否为 Live Photo
    if (!Platform.isIOS || (asset.subtype & 8) == 0) return null;

    return asset.fileWithSubtype;
  }

  /// 获取 Live Photo 的视频 URL（用于播放）
  Future<String?> getLivePhotoVideoUrl(String assetId) async {
    final asset = _assetCache[assetId];
    if (asset == null) return null;

    // 检测是否为 Live Photo
    if (!Platform.isIOS || (asset.subtype & 8) == 0) return null;

    return asset.getMediaUrl();
  }

  @override
  Future<Stream<List<int>>> getFileStream(String path, {FileRange? range}) async {
    // 解码 asset ID
    final assetId = _decodeId(path.split('/').last);
    var asset = _assetCache[assetId];

    // 如果缓存中没有，尝试从系统获取
    if (asset == null) {
      asset = await pm.AssetEntity.fromId(assetId);
      if (asset == null) {
        throw Exception('Asset not found: $assetId');
      }
      _assetCache[assetId] = asset;
    }

    final file = await asset.file;
    if (file == null) {
      throw Exception('Cannot get file for asset: $assetId');
    }

    // 处理范围请求
    if (range != null) {
      return _getFileStreamWithRange(file, range);
    }

    return file.openRead();
  }

  Future<Stream<List<int>>> _getFileStreamWithRange(File file, FileRange range) async {
    final length = await file.length();
    final end = range.end ?? length - 1;

    return file.openRead(range.start, end + 1);
  }

  @override
  Future<String> getFileUrl(String path, {Duration? expiry}) async {
    // 解码 asset ID
    final assetId = _decodeId(path.split('/').last);
    var asset = _assetCache[assetId];

    // 如果缓存中没有，尝试从系统获取
    if (asset == null) {
      asset = await pm.AssetEntity.fromId(assetId);
      if (asset == null) {
        throw Exception('Asset not found: $assetId');
      }
      _assetCache[assetId] = asset;
    }

    final file = await asset.file;
    if (file == null) {
      throw Exception('Cannot get file for asset: $assetId');
    }

    // 返回本地文件 URL
    return file.uri.toString();
  }

  @override
  Future<String?> getThumbnailUrl(String path, {ThumbnailSize? size}) async {
    // 解码 asset ID
    final assetId = _decodeId(path.split('/').last);
    final asset = _assetCache[assetId];

    if (asset == null) return null;

    // photo_manager 不支持缩略图 URL，返回 null
    // 使用者需要通过 asset.thumbnailData 获取缩略图
    return null;
  }

  /// 获取资源的缩略图数据
  @override
  Future<Uint8List?> getThumbnailData(String path, {fs.ThumbnailSize? size}) async {
    // 解码 asset ID
    final assetId = _decodeId(path.split('/').last);
    var asset = _assetCache[assetId];

    // 如果缓存中没有，尝试从系统获取
    if (asset == null) {
      asset = await pm.AssetEntity.fromId(assetId);
      if (asset == null) return null;
      _assetCache[assetId] = asset;
    }

    final thumbnailSize = size ?? fs.ThumbnailSize.medium;
    final pixelSize = thumbnailSize.pixels;
    return asset.thumbnailDataWithSize(
      pm.ThumbnailSize(pixelSize, pixelSize),
    );
  }

  @override
  Future<Stream<List<int>>> getUrlStream(String url) {
    throw UnimplementedError('相册不支持 URL 流访问');
  }

  /// 获取资源实体
  Future<pm.AssetEntity?> getAsset(String assetId) async {
    if (_assetCache.containsKey(assetId)) {
      return _assetCache[assetId];
    }

    // 尝试从系统获取
    final asset = await pm.AssetEntity.fromId(assetId);
    if (asset != null) {
      _assetCache[assetId] = asset;
    }
    return asset;
  }

  // ==================== 不支持的写操作 ====================

  @override
  Future<void> createDirectory(String path) async {
    throw UnsupportedError('相册不支持创建目录');
  }

  @override
  Future<void> delete(String path) async {
    throw UnsupportedError('相册不支持删除操作（请使用系统相册App）');
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    throw UnsupportedError('相册不支持重命名');
  }

  @override
  Future<void> copy(String sourcePath, String destPath) async {
    throw UnsupportedError('相册不支持复制');
  }

  @override
  Future<void> move(String sourcePath, String destPath) async {
    throw UnsupportedError('相册不支持移动');
  }

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    throw UnsupportedError('相册不支持上传（请使用系统相册App）');
  }

  @override
  Future<void> writeFile(String remotePath, List<int> data) async {
    throw UnsupportedError('相册不支持写入');
  }

  @override
  Future<List<FileItem>> search(String query, {String? path}) async {
    // 分批搜索，避免一次性加载所有资源
    final albums = await _getAlbums();
    final allAlbum = albums.firstWhere((a) => a.isAll, orElse: () => albums.first);
    final count = await allAlbum.assetCountAsync;

    final results = <FileItem>[];
    final queryLower = query.toLowerCase();

    // 分批加载资源
    const batchSize = 100;
    for (var start = 0; start < count; start += batchSize) {
      final end = (start + batchSize > count) ? count : start + batchSize;
      final assets = await allAlbum.getAssetListRange(start: start, end: end);

      for (final asset in assets) {
        final assetTitle = asset.title;
        final titleLower = assetTitle?.toLowerCase() ?? '';
        if (titleLower.contains(queryLower)) {
          _assetCache[asset.id] = asset;

          // 提取扩展名（不调用 asset.file 避免阻塞）
          String? extension;
          if (assetTitle != null && assetTitle.contains('.')) {
            extension = assetTitle.split('.').last.toLowerCase();
          } else if (asset.mimeType != null) {
            final parts = asset.mimeType!.split('/');
            if (parts.length == 2) {
              extension = parts[1].toLowerCase();
            }
          }

          // 检测是否为 Live Photo
          final isLivePhoto = Platform.isIOS && (asset.subtype & 8) != 0;

          // 对 asset ID 进行编码
          final encodedAssetId = _encodeId(asset.id);

          // 使用估算的文件大小
          final estimatedSize = asset.width * asset.height * 4 ~/ 10;

          results.add(FileItem(
            name: assetTitle ?? asset.id,
            path: '/all/$encodedAssetId',
            isDirectory: false,
            size: estimatedSize,
            modifiedTime: asset.modifiedDateTime,
            extension: extension,
            mimeType: asset.mimeType,
            isLivePhoto: isLivePhoto,
            livePhotoVideoPath: null, // 延迟加载
          ));
        }
      }

      // 让出主线程
      await Future<void>.delayed(Duration.zero);
    }

    return results;
  }
}
