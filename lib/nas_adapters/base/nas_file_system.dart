import 'dart:typed_data';

/// 文件系统抽象接口
abstract class NasFileSystem {
  /// 列出目录内容
  Future<List<FileItem>> listDirectory(String path);

  /// 获取文件信息
  Future<FileItem> getFileInfo(String path);

  /// 获取文件下载流
  Future<Stream<List<int>>> getFileStream(String path, {FileRange? range});

  /// 通过 URL 获取数据流
  ///
  /// 用于在需要绕过证书验证等场景下，通过已知 URL 获取数据
  /// 默认实现抛出 UnimplementedError，子类可按需实现
  Future<Stream<List<int>>> getUrlStream(String url) {
    throw UnimplementedError('getUrlStream is not implemented');
  }

  /// 获取文件直接访问 URL
  Future<String> getFileUrl(String path, {Duration? expiry});

  /// 创建目录
  Future<void> createDirectory(String path);

  /// 删除文件或目录
  Future<void> delete(String path);

  /// 重命名文件或目录
  Future<void> rename(String oldPath, String newPath);

  /// 复制文件或目录
  Future<void> copy(String sourcePath, String destPath);

  /// 移动文件或目录
  Future<void> move(String sourcePath, String destPath);

  /// 上传文件
  /// [localPath] 本地文件路径
  /// [remotePath] 远程目标目录路径
  /// [fileName] 文件名（可选，默认使用本地文件名）
  /// [onProgress] 上传进度回调 (已上传字节数, 总字节数)
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  });

  /// 写入字节数据到远程文件
  ///
  /// 直接将内存中的字节数据写入到远程文件，适用于：
  /// - 写入生成的 NFO 文件
  /// - 写入下载的海报图片
  ///
  /// [remotePath] 远程文件完整路径（包含文件名）
  /// [data] 要写入的字节数据
  ///
  /// 如果文件已存在，将被覆盖
  Future<void> writeFile(String remotePath, List<int> data);

  /// 搜索文件
  Future<List<FileItem>> search(String query, {String? path});

  /// 获取缩略图 URL
  Future<String?> getThumbnailUrl(String path, {ThumbnailSize? size});

  /// 获取缩略图数据
  ///
  /// 直接返回缩略图的字节数据，用于本地相册等不支持 HTTP URL 的场景。
  /// 默认实现返回 null，子类可按需实现。
  ///
  /// [path] 文件路径
  /// [size] 缩略图尺寸（可选，默认 medium）
  Future<Uint8List?> getThumbnailData(String path, {ThumbnailSize? size}) => Future.value();
}

/// 文件项
class FileItem {
  const FileItem({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    this.modifiedTime,
    this.createdTime,
    this.mimeType,
    this.extension,
    this.thumbnailUrl,
    this.isHidden = false,
    this.isReadOnly = false,
    this.isLivePhoto = false,
    this.livePhotoVideoPath,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime? modifiedTime;
  final DateTime? createdTime;
  final String? mimeType;
  final String? extension;
  final String? thumbnailUrl;
  final bool isHidden;
  final bool isReadOnly;

  /// 是否为 iOS Live Photo（实况照片）
  final bool isLivePhoto;

  /// Live Photo 的视频路径（仅当 isLivePhoto 为 true 时有效）
  final String? livePhotoVideoPath;

  bool get isFile => !isDirectory;

  FileType get type {
    if (isDirectory) return FileType.folder;

    // 先尝试从扩展名判断
    final typeFromExt = FileType.fromExtension(extension ?? '');
    if (typeFromExt != FileType.other) return typeFromExt;

    // 如果扩展名无法判断，尝试从 mimeType 判断
    if (mimeType != null) {
      final typeFromMime = FileType.fromMimeType(mimeType!);
      if (typeFromMime != FileType.other) return typeFromMime;
    }

    return FileType.other;
  }

  String get displaySize {
    if (isDirectory) return '';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var unitIndex = 0;
    var displaySize = size.toDouble();
    while (displaySize >= 1024 && unitIndex < units.length - 1) {
      displaySize /= 1024;
      unitIndex++;
    }
    return '${displaySize.toStringAsFixed(displaySize < 10 ? 1 : 0)} ${units[unitIndex]}';
  }
}

/// 文件类型
enum FileType {
  folder,
  image,
  video,
  audio,
  document,
  archive,
  code,
  text,
  pdf,
  epub,
  comic,
  other;

  static FileType fromExtension(String ext) {
    final e = ext.toLowerCase().replaceAll('.', '');
    return switch (e) {
      'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'bmp' || 'svg' ||
      'heic' || 'heif' ||  // iOS 默认格式
      'tiff' || 'tif' ||   // TIFF 格式
      'raw' || 'cr2' || 'nef' || 'arw' || 'dng' =>  // RAW 格式
        FileType.image,
      'mp4' ||
      'mkv' ||
      'avi' ||
      'mov' ||
      'wmv' ||
      'flv' ||
      'webm' ||
      'rmvb' ||
      'ts' ||
      'm2ts' =>
        FileType.video,
      'mp3' ||
      'flac' ||
      'wav' ||
      'aac' ||
      'm4a' ||
      'ogg' ||
      'wma' ||
      'ape' ||
      'aiff' ||
      'dsd' ||
      'ncm' ||    // 网易云音乐加密格式
      'dsf' ||    // DSD 格式
      'dff' ||    // DSD 格式
      'alac' ||   // Apple Lossless
      'opus' ||   // Opus 编码
      'mka' ||    // Matroska 音频
      'cue' =>    // CUE 分轨文件
        FileType.audio,
      'doc' || 'docx' || 'xls' || 'xlsx' || 'ppt' || 'pptx' => FileType.document,
      'zip' || 'rar' || '7z' || 'tar' || 'gz' || 'bz2' => FileType.archive,
      'cbz' || 'cbr' => FileType.comic,
      'dart' ||
      'js' ||
      'ts' ||
      'py' ||
      'java' ||
      'kt' ||
      'swift' ||
      'go' ||
      'rs' ||
      'c' ||
      'cpp' ||
      'h' ||
      'css' ||
      'html' ||
      'xml' ||
      'json' ||
      'yaml' ||
      'yml' =>
        FileType.code,
      'txt' || 'md' || 'log' => FileType.text,
      'pdf' => FileType.pdf,
      'epub' || 'mobi' || 'azw3' || 'fb2' => FileType.epub,
      _ => FileType.other,
    };
  }

  /// 根据 MIME 类型判断文件类型
  static FileType fromMimeType(String mimeType) {
    final mime = mimeType.toLowerCase();

    // 图片类型
    if (mime.startsWith('image/')) return FileType.image;

    // 视频类型
    if (mime.startsWith('video/')) return FileType.video;

    // 音频类型
    if (mime.startsWith('audio/')) return FileType.audio;

    // 文档类型
    if (mime == 'application/pdf') return FileType.pdf;
    if (mime == 'application/epub+zip') return FileType.epub;
    if (mime.contains('word') ||
        mime.contains('excel') ||
        mime.contains('powerpoint') ||
        mime.contains('spreadsheet') ||
        mime.contains('presentation')) {
      return FileType.document;
    }

    // 压缩包
    if (mime == 'application/zip' ||
        mime == 'application/x-rar-compressed' ||
        mime == 'application/x-7z-compressed' ||
        mime == 'application/gzip' ||
        mime == 'application/x-tar') {
      return FileType.archive;
    }

    // 文本类型
    if (mime.startsWith('text/')) return FileType.text;

    return FileType.other;
  }
}

/// 文件范围 (用于断点续传)
class FileRange {
  const FileRange({required this.start, this.end});

  final int start;
  final int? end;
}

/// 缩略图尺寸
enum ThumbnailSize {
  small(120),
  medium(240),
  large(480),
  xlarge(720);

  const ThumbnailSize(this.pixels);
  final int pixels;
}
