import 'package:my_nas/nas_adapters/base/nas_connection.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// NAS 适配器类型
enum NasAdapterType {
  synology,
  ugreen,
  fnos,
  qnap,
  webdav,
  smb,
  ftp,
  sftp,
  local,
}

/// NAS 适配器信息
class NasAdapterInfo {
  const NasAdapterInfo({
    required this.type,
    required this.name,
    required this.version,
    this.supportsMediaService = false,
    this.supportsToolsService = false,
  });

  final NasAdapterType type;
  final String name;
  final String version;
  final bool supportsMediaService;
  final bool supportsToolsService;
}

/// NAS 适配器抽象接口
abstract class NasAdapter {
  /// 适配器信息
  NasAdapterInfo get info;

  /// 连接状态
  bool get isConnected;

  /// 当前连接配置
  ConnectionConfig? get connection;

  /// 连接管理
  Future<ConnectionResult> connect(ConnectionConfig config);
  Future<void> disconnect();

  /// 检查连接健康状态
  ///
  /// 实际测试连接是否有效（如列出目录），而不仅仅检查状态标志。
  /// 用于检测设备休眠后连接是否仍然有效。
  ///
  /// 返回 true 表示连接健康，false 表示连接已断开或异常。
  Future<bool> checkConnectionHealth();

  /// 文件系统操作
  NasFileSystem get fileSystem;

  /// 媒体服务 (可选实现)
  MediaService? get mediaService => null;

  /// 下载工具服务 (可选实现)
  ToolsService? get toolsService => null;

  /// 获取存储信息 (可选实现)
  ///
  /// 返回 NAS 的存储容量信息，包括总容量、已使用容量等。
  /// 不支持的适配器返回 null。
  Future<StorageInfo?> getStorageInfo() async => null;

  /// 资源释放
  Future<void> dispose();
}

/// 媒体服务接口
abstract class MediaService {
  /// 获取视频库
  Future<List<MediaLibrary>> getVideoLibraries();

  /// 获取音乐库
  Future<List<MediaLibrary>> getMusicLibraries();

  /// 获取转码流 URL
  Future<String?> getTranscodedStreamUrl(
    String fileId,
    TranscodeOptions options,
  );
}

/// 下载工具服务接口
abstract class ToolsService {
  /// 获取支持的工具列表
  List<ToolInfo> get supportedTools;

  /// 检查工具是否可用
  Future<bool> isToolAvailable(ToolType type);
}

/// 存储信息
class StorageInfo {
  const StorageInfo({
    required this.totalBytes,
    required this.usedBytes,
    this.volumes = const [],
  });

  /// 总容量（字节）
  final int totalBytes;

  /// 已使用容量（字节）
  final int usedBytes;

  /// 卷列表（如果支持多卷）
  final List<VolumeInfo> volumes;

  /// 可用容量（字节）
  int get freeBytes => totalBytes - usedBytes;

  /// 使用百分比 (0.0 - 1.0)
  double get usagePercent =>
      totalBytes > 0 ? usedBytes / totalBytes : 0.0;
}

/// 卷信息
class VolumeInfo {
  const VolumeInfo({
    required this.id,
    required this.name,
    required this.totalBytes,
    required this.usedBytes,
    this.status,
    this.fileSystem,
  });

  final String id;
  final String name;
  final int totalBytes;
  final int usedBytes;
  final String? status;
  final String? fileSystem;

  int get freeBytes => totalBytes - usedBytes;

  double get usagePercent =>
      totalBytes > 0 ? usedBytes / totalBytes : 0.0;
}

/// 媒体库
class MediaLibrary {
  const MediaLibrary({
    required this.id,
    required this.name,
    required this.type,
    this.itemCount,
  });

  final String id;
  final String name;
  final MediaLibraryType type;
  final int? itemCount;
}

enum MediaLibraryType { video, music, photo }

/// 转码选项
class TranscodeOptions {
  const TranscodeOptions({
    this.quality,
    this.format,
    this.audioTrack,
    this.subtitleTrack,
  });

  final String? quality;
  final String? format;
  final int? audioTrack;
  final int? subtitleTrack;
}

/// 工具信息
class ToolInfo {
  const ToolInfo({
    required this.type,
    required this.name,
    this.version,
    this.isAvailable = false,
  });

  final ToolType type;
  final String name;
  final String? version;
  final bool isAvailable;
}

enum ToolType {
  nasTools,
  qbittorrent,
  transmission,
  aria2,
}
