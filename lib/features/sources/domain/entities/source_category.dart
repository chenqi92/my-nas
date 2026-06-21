import 'package:flutter/material.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';

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
        nasDevices => appL10n.sourceCategoryDescNasDevices,
        genericProtocols => appL10n.sourceCategoryDescGenericProtocols,
        localStorage => appL10n.sourceCategoryDescLocalStorage,
        mediaServers => appL10n.sourceCategoryDescMediaServers,
        downloadTools => appL10n.sourceCategoryDescDownloadTools,
        mediaTracking => appL10n.sourceCategoryDescMediaTracking,
        mediaManagement => appL10n.sourceCategoryDescMediaManagement,
        ptSites => appL10n.sourceCategoryDescPtSites,
        subtitleSites => appL10n.sourceCategoryDescSubtitleSites,
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
