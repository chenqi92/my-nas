/// 自动删种相关数据模型
library;

import 'package:my_nas/core/i18n/app_l10n.dart';

/// 自动删种任务
class NtTorrentRemoverTask {
  const NtTorrentRemoverTask({
    required this.id,
    required this.name,
    this.action,
    this.interval,
    this.enabled,
    this.sameData,
    this.onlyNasTool,
    this.ratio,
    this.seedingTime,
    this.uploadAvs,
    this.size,
    this.savePathKey,
    this.trackerKey,
    this.downloader,
    this.qbState,
    this.qbCategory,
    this.trState,
    this.trErrorKey,
  });

  factory NtTorrentRemoverTask.fromJson(Map<String, dynamic> json) => NtTorrentRemoverTask(
        id: json['id'] as int? ?? json['tid'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        action: json['action'] as int?,
        interval: json['interval'] as int?,
        enabled: json['enabled'] as int?,
        sameData: json['samedata'] as int?,
        onlyNasTool: json['onlynastool'] as int?,
        ratio: (json['ratio'] as num?)?.toDouble(),
        seedingTime: json['seeding_time'] as int?,
        uploadAvs: json['upload_avs'] as int?,
        size: json['size'] as String?,
        savePathKey: json['savepath_key'] as String?,
        trackerKey: json['tracker_key'] as String?,
        downloader: json['downloader'] as String?,
        qbState: json['qb_state'] as String?,
        qbCategory: json['qb_category'] as String?,
        trState: json['tr_state'] as String?,
        trErrorKey: json['tr_error_key'] as String?,
      );

  final int id;
  final String name;
  final int? action;
  final int? interval;
  final int? enabled;
  final int? sameData;
  final int? onlyNasTool;
  final double? ratio;
  final int? seedingTime;
  final int? uploadAvs;
  final String? size;
  final String? savePathKey;
  final String? trackerKey;
  final String? downloader;
  final String? qbState;
  final String? qbCategory;
  final String? trState;
  final String? trErrorKey;

  /// 是否启用
  bool get isEnabled => enabled == 1;

  /// 动作描述
  String get actionText => switch (action) {
        1 => appL10n.nastoolRemoverPause,
        2 => appL10n.nastoolRemoverDeleteTorrent,
        3 => appL10n.nastoolRemoverDeleteTorrentFiles,
        _ => appL10n.nastoolUnknown,
      };
}
