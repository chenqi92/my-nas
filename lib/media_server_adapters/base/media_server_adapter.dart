import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/media_server_adapters/base/media_server_entities.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/service_adapters/base/service_adapter.dart';

/// 服务器版本信息
class ServerVersion implements Comparable<ServerVersion> {
  const ServerVersion(this.major, [this.minor = 0, this.patch = 0]);

  /// 从版本字符串解析
  /// 支持格式: "10.8.0", "10.8", "4.6.0.30-beta", "1.40.4.8679"
  factory ServerVersion.parse(String version) {
    // 移除可能的前缀 v
    var cleaned = version.startsWith('v') ? version.substring(1) : version;
    // 只取主版本号部分（去掉 -beta, -alpha 等后缀）
    cleaned = cleaned.split('-').first;
    // 分割版本号
    final parts = cleaned.split('.');
    return ServerVersion(
      parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0,
      parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0,
    );
  }

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(ServerVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator <(ServerVersion other) => compareTo(other) < 0;
  bool operator <=(ServerVersion other) => compareTo(other) <= 0;
  bool operator >(ServerVersion other) => compareTo(other) > 0;
  bool operator >=(ServerVersion other) => compareTo(other) >= 0;

  @override
  String toString() => '$major.$minor.$patch';
}

/// 服务器兼容性检查结果
class ServerCompatibilityResult {
  const ServerCompatibilityResult._({
    required this.isCompatible,
    this.serverVersion,
    this.minVersion,
    this.message,
    this.warnings = const [],
  });

  /// 兼容
  const ServerCompatibilityResult.compatible({
    required String serverVersion,
    List<String> warnings = const [],
  }) : this._(
          isCompatible: true,
          serverVersion: serverVersion,
          warnings: warnings,
        );

  /// 不兼容
  const ServerCompatibilityResult.incompatible({
    required String serverVersion,
    required String minVersion,
    required String message,
  }) : this._(
          isCompatible: false,
          serverVersion: serverVersion,
          minVersion: minVersion,
          message: message,
        );

  final bool isCompatible;
  final String? serverVersion;
  final String? minVersion;
  final String? message;
  final List<String> warnings;
}

/// 媒体服务器版本要求
class MediaServerVersionRequirements {
  const MediaServerVersionRequirements._();

  /// Jellyfin 最低版本要求
  static const jellyfinMin = ServerVersion(10, 8, 0);

  /// Emby 最低版本要求
  static const embyMin = ServerVersion(4, 6, 0);

  /// Plex 没有严格的版本要求，但建议使用最新版
  /// Plex 版本格式特殊，如 1.40.4.8679
  static const plexRecommended = ServerVersion(1, 32, 0);

  /// 检查 Jellyfin 版本兼容性
  static ServerCompatibilityResult checkJellyfin(String version) {
    final current = ServerVersion.parse(version);
    final warnings = <String>[];

    if (current < jellyfinMin) {
      return ServerCompatibilityResult.incompatible(
        serverVersion: version,
        minVersion: jellyfinMin.toString(),
        message: appL10n.mediaServerVersionTooLow('${jellyfinMin.major}.${jellyfinMin.minor}'),
      );
    }

    // Quick Connect 需要 10.7+，但我们已经要求 10.8+
    // WebSocket 需要特定版本
    if (current < const ServerVersion(10, 9, 0)) {
      warnings.add(appL10n.mediaServerJellyfinUpgradeHint);
    }

    return ServerCompatibilityResult.compatible(
      serverVersion: version,
      warnings: warnings,
    );
  }

  /// 检查 Emby 版本兼容性
  static ServerCompatibilityResult checkEmby(String version) {
    final current = ServerVersion.parse(version);
    final warnings = <String>[];

    if (current < embyMin) {
      return ServerCompatibilityResult.incompatible(
        serverVersion: version,
        minVersion: embyMin.toString(),
        message: appL10n.mediaServerVersionTooLow('${embyMin.major}.${embyMin.minor}'),
      );
    }

    // Emby 4.8+ 有更好的 API 支持
    if (current < const ServerVersion(4, 8, 0)) {
      warnings.add(appL10n.mediaServerEmbyUpgradeHint);
    }

    return ServerCompatibilityResult.compatible(
      serverVersion: version,
      warnings: warnings,
    );
  }

  /// 检查 Plex 版本兼容性
  /// Plex 版本格式: 1.40.4.8679
  static ServerCompatibilityResult checkPlex(String version) {
    final current = ServerVersion.parse(version);
    final warnings = <String>[];

    // Plex 通常向后兼容，但建议使用较新版本
    if (current < plexRecommended) {
      warnings.add(appL10n.mediaServerPlexUpgradeHint('${plexRecommended.major}.${plexRecommended.minor}'));
    }

    return ServerCompatibilityResult.compatible(
      serverVersion: version,
      warnings: warnings,
    );
  }
}

/// 媒体服务器适配器抽象基类
///
/// 继承自 ServiceAdapter，同时提供媒体服务器特有的功能：
/// - 媒体库浏览
/// - 视频流获取
/// - 播放状态报告
/// - 虚拟文件系统（用于文件浏览器兼容）
abstract class MediaServerAdapter implements ServiceAdapter {
  // === ServiceAdapter 接口实现 ===
  @override
  ServiceAdapterInfo get info;

  @override
  bool get isConnected;

  @override
  ServiceConnectionConfig? get connection;

  @override
  Future<ServiceConnectionResult> connect(ServiceConnectionConfig config);

  @override
  Future<void> disconnect();

  @override
  Future<void> dispose();

  // === 媒体服务器特有功能 ===

  /// 服务器类型
  SourceType get serverType;

  /// 当前用户 ID
  String? get userId;

  /// 服务器名称
  String? get serverName;

  /// 服务器版本
  String? get serverVersion;

  /// 获取所有媒体库
  Future<List<MediaLibrary>> getLibraries();

  /// 获取媒体库中的项目
  ///
  /// [libraryId] 媒体库 ID，如果为 null 则获取根目录
  /// [parentId] 父项目 ID，用于获取子项目（如剧集的季/集）
  /// [startIndex] 起始索引（用于分页）
  /// [limit] 每页数量
  /// [sortBy] 排序字段
  /// [sortOrder] 排序方向
  /// [includeItemTypes] 只包含指定类型
  Future<MediaItemsResult> getItems({
    String? libraryId,
    String? parentId,
    int startIndex = 0,
    int limit = 100,
    String? sortBy,
    String? sortOrder,
    List<MediaItemType>? includeItemTypes,
  });

  /// 获取单个项目详情
  Future<MediaItem> getItemDetail(String itemId);

  /// 获取图片 URL
  ///
  /// [itemId] 项目 ID
  /// [imageType] 图片类型
  /// [maxWidth] 最大宽度（可选，用于缩放）
  /// [maxHeight] 最大高度（可选，用于缩放）
  /// [tag] 图片标签（用于缓存验证）
  String getImageUrl(
    String itemId,
    MediaImageType imageType, {
    int? maxWidth,
    int? maxHeight,
    String? tag,
  });

  /// 获取视频流信息
  ///
  /// [itemId] 项目 ID
  /// [preferDirectPlay] 是否优先直接播放
  /// [maxStreamingBitrate] 最大码率限制
  Future<MediaStreamInfo> getStreamInfo(
    String itemId, {
    bool preferDirectPlay = true,
    int? maxStreamingBitrate,
  });

  /// 报告播放状态
  Future<void> reportPlayback(PlaybackReport report);

  /// 标记为已观看/未观看
  Future<void> setWatched(String itemId, bool watched);

  /// 标记为已观看（便捷方法）
  Future<void> markWatched(String itemId) => setWatched(itemId, true);

  /// 标记为未观看（便捷方法）
  Future<void> markUnwatched(String itemId) => setWatched(itemId, false);

  /// 切换收藏状态
  Future<bool> toggleFavorite(String itemId);

  /// 获取虚拟文件系统
  ///
  /// 将媒体库映射为文件系统结构，用于文件浏览器兼容
  NasFileSystem get virtualFileSystem;

  /// 搜索媒体
  ///
  /// [query] 搜索关键词
  /// [limit] 结果数量限制
  /// [includeItemTypes] 只搜索指定类型
  Future<MediaItemsResult> search(
    String query, {
    int limit = 20,
    List<MediaItemType>? includeItemTypes,
  });

  /// 获取推荐内容
  Future<MediaItemsResult> getRecommendations({int limit = 20});

  /// 获取最近添加的内容
  Future<MediaItemsResult> getLatestMedia({
    String? libraryId,
    int limit = 20,
    List<MediaItemType>? includeItemTypes,
  });

  /// 获取继续观看列表
  Future<MediaItemsResult> getResumeItems({int limit = 20});

  /// 获取下一集（用于连续剧）
  Future<MediaItem?> getNextUp({String? seriesId});

  /// 获取最近添加的内容（用于增量同步）
  Future<MediaItemsResult> getRecentlyAdded({int limit = 100});
}

/// 媒体服务器连接模式
enum MediaServerConnectionMode {
  /// 直连模式：数据按需获取，不本地缓存
  /// 优点：快速设置、实时更新、节省存储
  /// 缺点：需要网络、每次都要加载
  direct,

  /// 库模式：预缓存元数据到本地
  /// 优点：快速浏览、离线可用、可与本地刮削数据合并
  /// 缺点：首次同步慢、需要同步机制
  library,
}

/// 媒体服务器同步间隔
enum MediaServerSyncInterval {
  /// 手动同步
  manual,

  /// 每小时同步
  hourly,

  /// 每天同步
  daily,

  /// 每周同步
  weekly,
}

/// 媒体服务器连接配置扩展
extension MediaServerConnectionConfig on ServiceConnectionConfig {
  /// 获取用户 ID（从 extraConfig）
  String? get userId => extraConfig?['userId'] as String?;

  /// 获取访问令牌（从 extraConfig）
  String? get accessToken => extraConfig?['accessToken'] as String?;

  /// 是否优先直接播放
  bool get preferDirectPlay =>
      extraConfig?['preferDirectPlay'] as bool? ?? true;

  /// 最大码率限制
  int? get maxStreamingBitrate =>
      extraConfig?['maxStreamingBitrate'] as int?;

  /// 获取连接模式
  MediaServerConnectionMode get connectionMode {
    final mode = extraConfig?['connectionMode'] as String?;
    return switch (mode) {
      '库模式' || 'library' => MediaServerConnectionMode.library,
      _ => MediaServerConnectionMode.direct,
    };
  }

  /// 获取同步间隔
  MediaServerSyncInterval get syncInterval {
    final interval = extraConfig?['syncInterval'] as String?;
    return switch (interval) {
      '每小时' || 'hourly' => MediaServerSyncInterval.hourly,
      '每天' || 'daily' => MediaServerSyncInterval.daily,
      '每周' || 'weekly' => MediaServerSyncInterval.weekly,
      _ => MediaServerSyncInterval.manual,
    };
  }

  /// 同步间隔对应的 Duration
  Duration? get syncIntervalDuration => switch (syncInterval) {
        MediaServerSyncInterval.hourly => const Duration(hours: 1),
        MediaServerSyncInterval.daily => const Duration(days: 1),
        MediaServerSyncInterval.weekly => const Duration(days: 7),
        MediaServerSyncInterval.manual => null,
      };
}

/// 媒体服务器连接结果
sealed class MediaServerConnectionResult {
  const MediaServerConnectionResult();

  T when<T>({
    required T Function(MediaServerAdapter adapter) success,
    required T Function(String error) failure,
  }) =>
      switch (this) {
        MediaServerConnectionSuccess(:final adapter) => success(adapter),
        MediaServerConnectionFailure(:final error) => failure(error),
      };
}

class MediaServerConnectionSuccess extends MediaServerConnectionResult {
  const MediaServerConnectionSuccess(this.adapter);
  final MediaServerAdapter adapter;
}

class MediaServerConnectionFailure extends MediaServerConnectionResult {
  const MediaServerConnectionFailure(this.error);
  final String error;
}
