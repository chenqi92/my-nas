import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:my_nas/features/sources/domain/entities/source_category.dart';
import 'package:uuid/uuid.dart';

/// 源类型
///
/// 排列顺序按以下规则：
/// 1. NAS 设备类型（按品牌知名度排序）
/// 2. 通用协议类型
/// 3. 本地存储
/// 4. 服务类源（下载工具、媒体追踪、媒体管理）
enum SourceType {
  // === 存储类源 ===
  // NAS 设备
  synology('Synology NAS', 'synology'),
  qnap('QNAP NAS', 'qnap'),
  ugreen('绿联 NAS', 'ugreen'),
  fnos('飞牛 fnOS', 'fnos'),
  // 通用协议
  webdav('WebDAV', 'webdav'),
  smb('SMB/CIFS', 'smb'),
  ftp('FTP', 'ftp'),
  sftp('SFTP', 'sftp'),
  nfs('NFS', 'nfs'),
  // 媒体发现（无需认证）
  upnp('UPnP/DLNA', 'upnp'),
  // 本地存储（系统自动创建，代表本机）
  local('本机', 'local'),

  // === 服务类源 ===
  // 下载工具
  qbittorrent('qBittorrent', 'qbittorrent'),
  transmission('Transmission', 'transmission'),
  aria2('Aria2', 'aria2'),
  // 媒体追踪
  trakt('Trakt', 'trakt'),
  // 媒体管理
  nastool('NASTool', 'nastool'),
  moviepilot('MoviePilot', 'moviepilot'),
  jellyfin('Jellyfin', 'jellyfin'),
  emby('Emby', 'emby'),
  plex('Plex', 'plex'),
  // PT 站点（通用类型，用户自行配置）
  ptSite('资源站点', 'pt_site'),
  // 字幕站点
  opensubtitles('OpenSubtitles', 'opensubtitles');

  const SourceType(this.displayName, this.id);
  final String displayName;
  final String id;

  /// 获取该源类型的默认端口
  int get defaultPort => switch (this) {
        // NAS 设备
        SourceType.synology => 5001,
        SourceType.ugreen => 9999,
        SourceType.fnos => 5666,
        SourceType.qnap => 8080,
        // 通用协议
        SourceType.webdav => 443,
        SourceType.smb => 445,
        SourceType.ftp => 21,
        SourceType.sftp => 22,
        SourceType.nfs => 2049,
        SourceType.upnp => 0, // 自动发现，无固定端口
        // 本地存储
        SourceType.local => 0,
        // 下载工具
        SourceType.qbittorrent => 8080,
        SourceType.transmission => 9091,
        SourceType.aria2 => 6800,
        // 媒体追踪
        SourceType.trakt => 443,
        // 媒体管理
        SourceType.nastool => 3000,
        SourceType.moviepilot => 3001,
        SourceType.jellyfin => 8096,
        SourceType.emby => 8096,
        SourceType.plex => 32400,
        // PT 站点（默认使用 HTTPS 443）
        SourceType.ptSite => 443,
        // 字幕站点
        SourceType.opensubtitles => 443,
      };

  /// 该源类型是否已实现
  ///
  /// 注：与 [SourceManagerService._createAdapter] 保持同步——只有这里返回
  /// true 的类型才会出现在 UI 选择器中，否则用户选了之后会落入
  /// UnsupportedError。
  bool get isSupported => switch (this) {
        // NAS 设备
        SourceType.synology => true,
        SourceType.ugreen => false, // 绿联 API 系逆向工程获得，暂不开放
        SourceType.fnos => false, // 飞牛OS暂未提供API
        SourceType.qnap => true,
        // 通用协议
        SourceType.webdav => true,
        SourceType.smb => true,
        // ftp/sftp/nfs/upnp 在 SourceManagerService 中尚未接入对应 adapter，
        // UI 暂屏蔽——避免用户选了之后连接报 UnsupportedError
        SourceType.ftp => false,
        SourceType.sftp => false,
        SourceType.nfs => false,
        SourceType.upnp => false,
        // 本地存储
        SourceType.local => true,
        // 下载工具
        SourceType.qbittorrent => true,
        SourceType.transmission => true,
        SourceType.aria2 => true,
        // 媒体追踪
        SourceType.trakt => true,
        // 媒体管理
        SourceType.nastool => true,
        SourceType.moviepilot => true,
        SourceType.jellyfin => true,
        SourceType.emby => true,
        SourceType.plex => true,
        // PT 站点
        SourceType.ptSite => true,
        // 字幕站点
        SourceType.opensubtitles => true,
      };

  /// 获取源类型所属的分组
  SourceCategory get category => switch (this) {
        // NAS 设备
        SourceType.synology ||
        SourceType.qnap ||
        SourceType.ugreen ||
        SourceType.fnos =>
          SourceCategory.nasDevices,
        // 通用协议
        SourceType.webdav ||
        SourceType.smb ||
        SourceType.ftp ||
        SourceType.sftp ||
        SourceType.nfs ||
        SourceType.upnp =>
          SourceCategory.genericProtocols,
        // 本地存储
        SourceType.local => SourceCategory.localStorage,
        // 媒体服务器
        SourceType.jellyfin ||
        SourceType.emby ||
        SourceType.plex =>
          SourceCategory.mediaServers,
        // 下载工具
        SourceType.qbittorrent ||
        SourceType.transmission ||
        SourceType.aria2 =>
          SourceCategory.downloadTools,
        // 媒体追踪
        SourceType.trakt => SourceCategory.mediaTracking,
        // 媒体管理
        SourceType.nastool ||
        SourceType.moviepilot =>
          SourceCategory.mediaManagement,
        // PT 站点
        SourceType.ptSite => SourceCategory.ptSites,
        // 字幕站点
        SourceType.opensubtitles => SourceCategory.subtitleSites,
      };

  /// 是否支持文件系统访问
  bool get supportsFileSystem => switch (this) {
        SourceType.synology ||
        SourceType.qnap ||
        SourceType.ugreen ||
        SourceType.fnos ||
        SourceType.webdav ||
        SourceType.smb ||
        SourceType.ftp ||
        SourceType.sftp ||
        SourceType.nfs ||
        SourceType.upnp ||
        SourceType.local =>
          true,
        _ => false,
      };

  /// 当前平台是否可用此源类型（用于连接源管理页面过滤）
  ///
  /// - 本地存储 (local)：由系统自动创建，不在添加源页面显示
  bool get isAvailableOnCurrentPlatform {
    // Web 平台不支持本地存储
    if (kIsWeb) {
      return this != SourceType.local;
    }
    // 本地存储由系统自动创建，不在添加源页面显示
    if (this == SourceType.local) {
      return false;
    }
    return true;
  }

  /// 是否为服务类源
  bool get isServiceSource => category.isServiceCategory;

  /// 获取源类型的图标
  IconData get icon => switch (this) {
        // NAS 设备
        SourceType.synology => Icons.storage,
        SourceType.qnap => Icons.storage,
        SourceType.ugreen => Icons.storage,
        SourceType.fnos => Icons.storage,
        // 通用协议
        SourceType.webdav => Icons.cloud,
        SourceType.smb => Icons.lan,
        SourceType.ftp => Icons.upload_file,
        SourceType.sftp => Icons.security,
        SourceType.nfs => Icons.share,
        SourceType.upnp => Icons.cast,
        // 本地存储
        SourceType.local => Icons.smartphone,
        // 下载工具
        SourceType.qbittorrent => Icons.download,
        SourceType.transmission => Icons.download,
        SourceType.aria2 => Icons.download,
        // 媒体追踪
        SourceType.trakt => Icons.track_changes,
        // 媒体管理
        SourceType.nastool => Icons.video_library,
        SourceType.moviepilot => Icons.video_library,
        SourceType.jellyfin => Icons.live_tv,
        SourceType.emby => Icons.live_tv,
        SourceType.plex => Icons.live_tv,
        // PT 站点
        SourceType.ptSite => Icons.rss_feed,
        // 字幕站点
        SourceType.opensubtitles => Icons.subtitles,
      };

  /// 获取源类型的主题颜色（用于快速区分不同协议）
  Color get themeColor => switch (this) {
        // NAS 设备 - 蓝色系（品牌感）
        SourceType.synology => const Color(0xFF1976D2), // 深蓝
        SourceType.qnap => const Color(0xFF0288D1), // 浅蓝
        SourceType.ugreen => const Color(0xFF4CAF50), // 绿联绿
        SourceType.fnos => const Color(0xFF00BCD4), // 青色
        // 通用协议 - 各自特征色
        SourceType.webdav => const Color(0xFF9C27B0), // 紫色 - 云协议
        SourceType.smb => const Color(0xFFFF9800), // 橙色 - Windows/网络
        SourceType.ftp => const Color(0xFF795548), // 棕色 - 传统协议
        SourceType.sftp => const Color(0xFF607D8B), // 蓝灰 - 安全协议
        SourceType.nfs => const Color(0xFF009688), // 青绿 - Unix协议
        SourceType.upnp => const Color(0xFFE91E63), // 粉红 - 媒体发现
        // 本地存储 - 蓝色
        SourceType.local => const Color(0xFF2196F3),
        // 下载工具 - 绿色系
        SourceType.qbittorrent => const Color(0xFF2196F3), // qB蓝
        SourceType.transmission => const Color(0xFFFF5722), // Tr橙红
        SourceType.aria2 => const Color(0xFF8BC34A), // 浅绿
        // 媒体追踪 - 红色
        SourceType.trakt => const Color(0xFFED1C24), // Trakt红
        // 媒体管理 - 各品牌色
        SourceType.nastool => const Color(0xFF673AB7), // 深紫
        SourceType.moviepilot => const Color(0xFF3F51B5), // 靛蓝
        SourceType.jellyfin => const Color(0xFF00A4DC), // Jellyfin紫蓝
        SourceType.emby => const Color(0xFF52B54B), // Emby绿
        SourceType.plex => const Color(0xFFE5A00D), // Plex橙黄
        // PT 站点 - 琥珀色
        SourceType.ptSite => const Color(0xFFFFA000),
        // 字幕站点 - 绿色
        SourceType.opensubtitles => const Color(0xFF4CAF50),
      };

  /// 获取源类型的描述
  String get description => switch (this) {
        // NAS 设备
        SourceType.synology => '群晖 NAS，支持 DSM 6/7',
        SourceType.qnap => '威联通 NAS',
        SourceType.ugreen => '绿联私有云 NAS',
        SourceType.fnos => '飞牛 fnOS 系统',
        // 通用协议
        SourceType.webdav => '支持 WebDAV 协议的服务器',
        SourceType.smb => 'Windows 共享文件夹协议',
        SourceType.ftp => '文件传输协议（支持 TLS 加密）',
        SourceType.sftp => '基于 SSH 的安全文件传输',
        SourceType.nfs => '网络文件系统',
        SourceType.upnp => '自动发现局域网媒体设备',
        // 本地存储
        SourceType.local => '本机存储，手机端自动获取系统媒体库',
        // 下载工具
        SourceType.qbittorrent => '开源远程下载客户端',
        SourceType.transmission => '轻量级远程下载客户端',
        SourceType.aria2 => '多协议下载客户端',
        // 媒体追踪
        SourceType.trakt => '追踪观看记录和媒体状态',
        // 媒体管理
        SourceType.nastool => 'NAS 媒体库管理工具',
        SourceType.moviepilot => '影视自动化管理工具',
        SourceType.jellyfin => '开源媒体服务器',
        SourceType.emby => '媒体服务器',
        SourceType.plex => '媒体服务器',
        // PT 站点
        SourceType.ptSite => '自定义资源站点',
        // 字幕站点
        SourceType.opensubtitles => '全球最大的字幕数据库',
      };

  /// 是否默认使用 SSL
  bool get defaultUseSsl => switch (this) {
        SourceType.synology ||
        SourceType.webdav ||
        SourceType.trakt ||
        // PT 站点都使用 HTTPS
        SourceType.ptSite ||
        // 字幕站点使用 HTTPS
        SourceType.opensubtitles =>
          true,
        _ => false,
      };

  /// 是否需要用户名（有些服务可能只需要 API Key 或 Cookie）
  bool get requiresUsername => switch (this) {
        SourceType.trakt ||
        SourceType.aria2 ||
        // UPnP 自动发现无需认证
        SourceType.upnp ||
        // 本地存储无需认证
        SourceType.local ||
        // PT 站点使用 API 或 Cookie 认证，不需要用户名
        SourceType.ptSite ||
        // 字幕站点使用 API Key 认证
        SourceType.opensubtitles =>
          false,
        _ => true,
      };

  /// 是否需要连接配置（主机、端口等）
  /// 本地存储不需要配置连接信息
  bool get requiresConnectionConfig => switch (this) {
        SourceType.local ||
        // 字幕站点使用固定的 API 地址
        SourceType.opensubtitles =>
          false,
        _ => true,
      };

  /// 获取该分组下的所有源类型
  static List<SourceType> byCategory(SourceCategory category) => SourceType.values
        .where((type) => type.category == category)
        .toList();
}

/// 源连接状态
enum SourceStatus {
  disconnected,
  connecting,
  requires2FA,
  connected,
  error,
}

/// 连接源实体
class SourceEntity {
  SourceEntity({
    required this.name,
    required this.type,
    required this.host,
    required this.username,
    String? id,
    this.port = 5001,
    this.useSsl = true,
    this.quickConnectId,
    this.lastConnected,
    this.autoConnect = true,
    this.rememberDevice = false,
    // OAuth 相关字段
    this.accessToken,
    this.refreshToken,
    this.tokenExpiresAt,
    // API Key 相关字段
    this.apiKey,
    // 额外配置
    this.extraConfig,
    // 排序顺序
    this.sortOrder = 0,
  }) : id = id ?? const Uuid().v4();

  factory SourceEntity.fromJson(Map<String, dynamic> json) => SourceEntity(
        id: json['id'] as String,
        name: json['name'] as String,
        type: SourceType.values.firstWhere(
          (t) => t.id == json['type'],
          orElse: () => SourceType.synology,
        ),
        host: json['host'] as String? ?? '',
        port: json['port'] as int? ?? 5001,
        username: json['username'] as String? ?? '',
        useSsl: json['useSsl'] as bool? ?? true,
        quickConnectId: json['quickConnectId'] as String?,
        lastConnected: json['lastConnected'] != null
            ? DateTime.parse(json['lastConnected'] as String)
            : null,
        autoConnect: json['autoConnect'] as bool? ?? true,
        rememberDevice: json['rememberDevice'] as bool? ?? false,
        // OAuth 相关字段
        accessToken: json['accessToken'] as String?,
        refreshToken: json['refreshToken'] as String?,
        tokenExpiresAt: json['tokenExpiresAt'] != null
            ? DateTime.parse(json['tokenExpiresAt'] as String)
            : null,
        // API Key 相关字段
        apiKey: json['apiKey'] as String?,
        // 额外配置 - 从 Hive 读取时需要安全转换类型
        extraConfig: json['extraConfig'] != null
            ? Map<String, dynamic>.from(json['extraConfig'] as Map)
            : null,
        // 排序顺序
        sortOrder: json['sortOrder'] as int? ?? 0,
      );

  final String id;
  final String name;
  final SourceType type;
  final String host;
  final int port;
  final String username;
  final bool useSsl;
  final String? quickConnectId;
  final DateTime? lastConnected;

  /// 是否自动连接（启动时自动连接）
  final bool autoConnect;

  /// 是否记住设备（跳过二次验证）
  final bool rememberDevice;

  // === OAuth 相关字段（用于 Trakt 等） ===

  /// OAuth 访问令牌
  final String? accessToken;

  /// OAuth 刷新令牌
  final String? refreshToken;

  /// 令牌过期时间
  final DateTime? tokenExpiresAt;

  // === API Key 相关字段（用于 qBittorrent v5.2+ 等） ===

  /// API Key
  final String? apiKey;

  // === 额外配置 ===

  /// 额外配置（JSON 格式，用于特殊配置）
  /// 例如：Trakt 的 Client ID/Secret，qBittorrent 的认证类型等
  final Map<String, dynamic>? extraConfig;

  // === 排序相关 ===

  /// 排序顺序（数值越小越靠前）
  final int sortOrder;

  String get displayName => name.isNotEmpty ? name : host;

  String get baseUrl {
    final protocol = useSsl ? 'https' : 'http';
    return '$protocol://$host:$port';
  }

  /// 获取唯一标识符（用于凭证存储）
  String get credentialKey => '${type.id}_${host}_${port}_$username';

  /// 是否为服务类源
  bool get isServiceSource => type.isServiceSource;

  /// 是否支持文件系统
  bool get supportsFileSystem => type.supportsFileSystem;

  /// OAuth 令牌是否需要刷新（提前 1 小时刷新）
  bool get needsTokenRefresh {
    if (tokenExpiresAt == null) return false;
    final expiresIn = tokenExpiresAt!.difference(DateTime.now());
    return expiresIn.inHours < 1;
  }

  /// OAuth 令牌是否已过期
  bool get isTokenExpired {
    if (tokenExpiresAt == null) return false;
    return DateTime.now().isAfter(tokenExpiresAt!);
  }

  /// 是否使用 API Key 认证
  bool get usesApiKey => apiKey != null && apiKey!.isNotEmpty;

  /// 是否使用 OAuth 认证
  bool get usesOAuth => accessToken != null && accessToken!.isNotEmpty;

  /// 获取文件浏览器的初始路径
  ///
  /// 根据源类型和配置返回初始浏览路径：
  /// - SMB: 如果配置了 shareName 返回 /{shareName}，否则返回 /（显示所有共享）
  /// - FTP/SFTP: 如果配置了 path 返回该路径，否则返回 /
  /// - WebDAV: 如果配置了 basePath 返回该路径，否则返回 /
  /// - 其他类型: 返回 /
  String get initialBrowsePath {
    switch (type) {
      case SourceType.smb:
        final shareName = extraConfig?['shareName'] as String?;
        if (shareName != null && shareName.isNotEmpty) {
          // shareName 可以包含子目录，如 "share" 或 "share/folder"
          final cleanPath = shareName.startsWith('/') ? shareName : '/$shareName';
          return cleanPath;
        }
        return '/';

      case SourceType.ftp:
      case SourceType.sftp:
        final path = extraConfig?['path'] as String?;
        if (path != null && path.isNotEmpty) {
          // 确保路径以 / 开头
          return path.startsWith('/') ? path : '/$path';
        }
        return '/';

      case SourceType.webdav:
        final basePath = extraConfig?['basePath'] as String?;
        if (basePath != null && basePath.isNotEmpty) {
          // 确保路径以 / 开头
          return basePath.startsWith('/') ? basePath : '/$basePath';
        }
        return '/';

      default:
        return '/';
    }
  }

  /// 是否配置了特定的浏览路径（非根目录）
  bool get hasCustomBrowsePath => initialBrowsePath != '/';

  SourceEntity copyWith({
    String? id,
    String? name,
    SourceType? type,
    String? host,
    int? port,
    String? username,
    bool? useSsl,
    String? quickConnectId,
    DateTime? lastConnected,
    bool? autoConnect,
    bool? rememberDevice,
    String? accessToken,
    String? refreshToken,
    DateTime? tokenExpiresAt,
    String? apiKey,
    Map<String, dynamic>? extraConfig,
    int? sortOrder,
  }) =>
      SourceEntity(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        useSsl: useSsl ?? this.useSsl,
        quickConnectId: quickConnectId ?? this.quickConnectId,
        lastConnected: lastConnected ?? this.lastConnected,
        autoConnect: autoConnect ?? this.autoConnect,
        rememberDevice: rememberDevice ?? this.rememberDevice,
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        tokenExpiresAt: tokenExpiresAt ?? this.tokenExpiresAt,
        apiKey: apiKey ?? this.apiKey,
        extraConfig: extraConfig ?? this.extraConfig,
        sortOrder: sortOrder ?? this.sortOrder,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.id,
        'host': host,
        'port': port,
        'username': username,
        'useSsl': useSsl,
        'quickConnectId': quickConnectId,
        'lastConnected': lastConnected?.toIso8601String(),
        'autoConnect': autoConnect,
        'rememberDevice': rememberDevice,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'tokenExpiresAt': tokenExpiresAt?.toIso8601String(),
        'apiKey': apiKey,
        'extraConfig': extraConfig,
        'sortOrder': sortOrder,
      };
}
