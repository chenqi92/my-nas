import 'package:flutter/material.dart';

/// 源分组类型
///
/// 用于在源类型选择页面中对源进行分组显示
enum SourceCategory {
  // === 存储类源 ===
  nasDevices('NAS 设备', 'nas_devices', Icons.storage),
  genericProtocols('通用协议', 'generic_protocols', Icons.link_rounded),
  localStorage('本机', 'local_storage', Icons.smartphone),
  mediaServers('媒体服务器', 'media_servers', Icons.live_tv),

  // === 服务类源 ===
  downloadTools('远程任务', 'download_tools', Icons.download_rounded),
  mediaTracking('媒体追踪', 'media_tracking', Icons.track_changes),
  mediaManagement('媒体管理', 'media_management', Icons.construction),
  ptSites('资源站点', 'pt_sites', Icons.rss_feed),
  subtitleSites('字幕站点', 'subtitle_sites', Icons.subtitles);

  const SourceCategory(this.displayName, this.id, this.icon);
  final String displayName;
  final String id;
  final IconData icon;

  /// 是否为服务类源分组
  bool get isServiceCategory => this == downloadTools ||
        this == mediaTracking ||
        this == mediaManagement ||
        this == ptSites ||
        this == subtitleSites;

  /// 是否为存储类源分组（包括媒体服务器）
  bool get isStorageCategory => !isServiceCategory;

  /// 获取分组的描述文本
  String get description => switch (this) {
        nasDevices => '连接到 NAS 设备，访问存储的媒体文件',
        genericProtocols => '通过通用协议连接到远程存储',
        localStorage => '访问本机存储，手机端自动获取系统媒体库',
        mediaServers => '连接到媒体服务器，播放视频内容',
        downloadTools => '管理下载任务和种子',
        mediaTracking => '追踪观看记录和媒体状态',
        mediaManagement => '自动化管理媒体库和订阅',
        ptSites => '连接资源站点获取内容',
        subtitleSites => '配置字幕下载站点',
      };
}

/// 源分组类型扩展
extension SourceCategoryExtension on SourceCategory {
  /// 获取分组下的所有存储类分组
  static List<SourceCategory> get storageCategories => [
        SourceCategory.nasDevices,
        SourceCategory.genericProtocols,
        SourceCategory.localStorage,
        SourceCategory.mediaServers,
      ];

  /// 获取分组下的所有服务类分组
  static List<SourceCategory> get serviceCategories => [
        SourceCategory.downloadTools,
        SourceCategory.mediaTracking,
        SourceCategory.mediaManagement,
        SourceCategory.ptSites,
        SourceCategory.subtitleSites,
      ];
}
