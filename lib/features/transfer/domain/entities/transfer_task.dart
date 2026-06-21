import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';

/// 传输任务类型
enum TransferType {
  /// 上传到 NAS
  upload,

  /// 下载到本地（完成后从列表移除）
  download,

  /// 缓存（保留在列表，支持离线播放）
  cache,
}

/// 传输任务状态
enum TransferStatus {
  /// 等待中
  pending,

  /// 排队中
  queued,

  /// 传输中
  transferring,

  /// 已暂停
  paused,

  /// 已完成
  completed,

  /// 失败
  failed,

  /// 已取消
  cancelled,
}

/// 统一传输任务
class TransferTask {
  TransferTask({
    required this.id,
    required this.type,
    required this.mediaType,
    required this.sourceId,
    required this.sourcePath,
    required this.fileName,
    required this.fileSize,
    required this.targetPath,
    required this.createdAt,
    this.targetSourceId,
    this.status = TransferStatus.pending,
    this.transferredBytes = 0,
    this.error,
    this.completedAt,
    this.assetId,
    this.songId,
    this.thumbnailPath,
  });

  /// 从 Map 创建（用于数据库读取）
  factory TransferTask.fromMap(Map<String, dynamic> map) => TransferTask(
        id: map['id'] as String,
        type: TransferType.values.byName(map['type'] as String),
        mediaType: MediaType.values.byName(map['media_type'] as String),
        sourceId: map['source_id'] as String,
        sourcePath: map['source_path'] as String,
        fileName: map['file_name'] as String,
        fileSize: map['file_size'] as int,
        targetSourceId: map['target_source_id'] as String?,
        targetPath: map['target_path'] as String,
        status: TransferStatus.values.byName(map['status'] as String),
        transferredBytes: map['transferred_bytes'] as int? ?? 0,
        error: map['error'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        completedAt: map['completed_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(map['completed_at'] as int)
            : null,
        assetId: map['asset_id'] as String?,
        songId: map['song_id'] as int?,
        thumbnailPath: map['thumbnail_path'] as String?,
      );

  /// 唯一标识
  final String id;

  /// 传输类型：上传/下载/缓存
  final TransferType type;

  /// 媒体类型：照片/音乐/图书/视频
  final MediaType mediaType;

  /// 源连接 ID
  final String sourceId;

  /// 源文件路径
  final String sourcePath;

  /// 文件名
  final String fileName;

  /// 文件大小（字节）
  final int fileSize;

  /// 目标连接 ID（上传时使用）
  final String? targetSourceId;

  /// 目标路径
  final String targetPath;

  /// 当前状态
  TransferStatus status;

  /// 已传输字节数
  int transferredBytes;

  /// 实时传输速度（字节/秒，运行期采样计算，不持久化）。
  int speed = 0;

  /// 错误信息
  String? error;

  /// 创建时间
  final DateTime createdAt;

  /// 完成时间
  DateTime? completedAt;

  /// photo_manager 资源 ID（用于删除本地照片）
  final String? assetId;

  /// on_audio_query 歌曲 ID（用于删除本地音乐）
  final int? songId;

  /// 缩略图路径（用于 UI 显示）
  final String? thumbnailPath;

  /// 传输进度 (0.0 - 1.0)
  double get progress => fileSize > 0 ? transferredBytes / fileSize : 0;

  /// 进度百分比文本
  String get progressText => '${(progress * 100).toStringAsFixed(1)}%';

  /// 是否正在传输
  bool get isTransferring => status == TransferStatus.transferring;

  /// 是否已完成
  bool get isCompleted => status == TransferStatus.completed;

  /// 是否失败
  bool get isFailed => status == TransferStatus.failed;

  /// 是否可以暂停
  bool get canPause =>
      status == TransferStatus.transferring || status == TransferStatus.queued;

  /// 是否可以继续
  bool get canResume => status == TransferStatus.paused;

  /// 是否可以重试
  bool get canRetry =>
      status == TransferStatus.failed || status == TransferStatus.cancelled;

  /// 是否可以取消
  bool get canCancel =>
      status == TransferStatus.pending ||
      status == TransferStatus.queued ||
      status == TransferStatus.transferring ||
      status == TransferStatus.paused;

  /// 格式化文件大小
  String get fileSizeText => _formatBytes(fileSize);

  /// 格式化已传输大小
  String get transferredText => _formatBytes(transferredBytes);

  /// 格式化大小进度
  String get sizeProgressText => '$transferredText / $fileSizeText';

  /// 传输类型显示名称
  String get typeDisplayName => switch (type) {
        TransferType.upload => appL10n.transferTypeUpload,
        TransferType.download => appL10n.transferTypeDownload,
        TransferType.cache => appL10n.transferTypeCache,
      };

  /// 状态显示名称
  String get statusDisplayName => switch (status) {
        TransferStatus.pending => '等待中',
        TransferStatus.queued => '排队中',
        TransferStatus.transferring => '传输中',
        TransferStatus.paused => '已暂停',
        TransferStatus.completed => '已完成',
        TransferStatus.failed => '失败',
        TransferStatus.cancelled => '已取消',
      };

  /// 复制并更新状态
  TransferTask copyWith({
    TransferStatus? status,
    int? transferredBytes,
    String? error,
    DateTime? completedAt,
  }) =>
      TransferTask(
        id: id,
        type: type,
        mediaType: mediaType,
        sourceId: sourceId,
        sourcePath: sourcePath,
        fileName: fileName,
        fileSize: fileSize,
        targetSourceId: targetSourceId,
        targetPath: targetPath,
        createdAt: createdAt,
        status: status ?? this.status,
        transferredBytes: transferredBytes ?? this.transferredBytes,
        error: error ?? this.error,
        completedAt: completedAt ?? this.completedAt,
        assetId: assetId,
        songId: songId,
        thumbnailPath: thumbnailPath,
      );

  /// 转换为 Map（用于数据库存储）
  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'media_type': mediaType.name,
        'source_id': sourceId,
        'source_path': sourcePath,
        'file_name': fileName,
        'file_size': fileSize,
        'target_source_id': targetSourceId,
        'target_path': targetPath,
        'status': status.name,
        'transferred_bytes': transferredBytes,
        'error': error,
        'created_at': createdAt.millisecondsSinceEpoch,
        'completed_at': completedAt?.millisecondsSinceEpoch,
        'asset_id': assetId,
        'song_id': songId,
        'thumbnail_path': thumbnailPath,
      };

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  String toString() =>
      'TransferTask(id: $id, type: $type, fileName: $fileName, status: $status, progress: $progressText)';
}

/// 传输进度事件
class TransferProgress {
  const TransferProgress({
    required this.taskId,
    required this.transferredBytes,
    required this.totalBytes,
    this.speed,
  });

  final String taskId;
  final int transferredBytes;
  final int totalBytes;

  /// 传输速度（字节/秒）
  final int? speed;

  double get progress => totalBytes > 0 ? transferredBytes / totalBytes : 0;

  String? get speedText {
    if (speed == null) return null;
    if (speed! < 1024) return '$speed B/s';
    if (speed! < 1024 * 1024) return '${(speed! / 1024).toStringAsFixed(1)} KB/s';
    return '${(speed! / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
}

/// 缓存的媒体项（用于离线播放列表）
class CachedMediaItem {
  const CachedMediaItem({
    required this.sourceId,
    required this.sourcePath,
    required this.mediaType,
    required this.fileName,
    required this.fileSize,
    required this.cachePath,
    required this.cachedAt,
    this.lastAccessed,
    this.title,
    this.artist,
    this.album,
    this.thumbnailPath,
  });

  factory CachedMediaItem.fromMap(Map<String, dynamic> map) => CachedMediaItem(
        sourceId: map['source_id'] as String,
        sourcePath: map['source_path'] as String,
        mediaType: MediaType.values.byName(map['media_type'] as String),
        fileName: map['file_name'] as String,
        fileSize: map['file_size'] as int,
        cachePath: map['cache_path'] as String,
        cachedAt: DateTime.fromMillisecondsSinceEpoch(map['cached_at'] as int),
        lastAccessed: map['last_accessed'] != null
            ? DateTime.fromMillisecondsSinceEpoch(map['last_accessed'] as int)
            : null,
        title: map['title'] as String?,
        artist: map['artist'] as String?,
        album: map['album'] as String?,
        thumbnailPath: map['thumbnail_path'] as String?,
      );

  final String sourceId;
  final String sourcePath;
  final MediaType mediaType;
  final String fileName;
  final int fileSize;
  final String cachePath;
  final DateTime cachedAt;
  final DateTime? lastAccessed;

  /// 媒体元数据（可选）
  final String? title;
  final String? artist;
  final String? album;
  final String? thumbnailPath;

  String get fileSizeText {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// 显示标题（优先使用 title，否则使用 fileName）
  String get displayTitle => title ?? fileName;

  Map<String, dynamic> toMap() => {
        'source_id': sourceId,
        'source_path': sourcePath,
        'media_type': mediaType.name,
        'file_name': fileName,
        'file_size': fileSize,
        'cache_path': cachePath,
        'cached_at': cachedAt.millisecondsSinceEpoch,
        'last_accessed': lastAccessed?.millisecondsSinceEpoch,
        'title': title,
        'artist': artist,
        'album': album,
        'thumbnail_path': thumbnailPath,
      };
}

/// 已上传标记
class UploadedMark {
  const UploadedMark({
    required this.localPath,
    required this.targetSourceId,
    required this.targetPath,
    required this.uploadedAt,
  });

  factory UploadedMark.fromMap(Map<String, dynamic> map) => UploadedMark(
        localPath: map['local_path'] as String,
        targetSourceId: map['target_source_id'] as String,
        targetPath: map['target_path'] as String,
        uploadedAt:
            DateTime.fromMillisecondsSinceEpoch(map['uploaded_at'] as int),
      );

  /// 本地文件路径（或 assetId）
  final String localPath;

  /// 上传目标连接 ID
  final String targetSourceId;

  /// 上传目标路径
  final String targetPath;

  /// 上传时间
  final DateTime uploadedAt;

  Map<String, dynamic> toMap() => {
        'local_path': localPath,
        'target_source_id': targetSourceId,
        'target_path': targetPath,
        'uploaded_at': uploadedAt.millisecondsSinceEpoch,
      };
}
