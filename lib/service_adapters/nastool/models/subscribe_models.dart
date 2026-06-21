/// 订阅相关数据模型
library;

import 'package:my_nas/core/i18n/app_l10n.dart';

/// 订阅信息
class NtSubscribe {
  const NtSubscribe({
    required this.id,
    required this.name,
    required this.type,
    this.tmdbId,
    this.year,
    this.season,
    this.state,
    this.posterPath,
    this.keyword,
    this.sites,
    this.filterRule,
    this.totalEp,
    this.currentEp,
  });

  factory NtSubscribe.fromJson(Map<String, dynamic> json, [String? defaultType]) => NtSubscribe(
    id: json['id'] is int ? json['id'] as int : (int.tryParse(json['id']?.toString() ?? '0') ?? 0),
    name: json['name'] as String? ?? json['title'] as String? ?? '',
    type: json['type'] as String? ?? defaultType ?? 'MOV',
    tmdbId: json['tmdbid']?.toString() ?? json['mediaid']?.toString(),
    year: json['year']?.toString(),
    season: json['season'] is int ? json['season'] as int : int.tryParse(json['season']?.toString() ?? ''),
    state: json['state'] as String?,
    posterPath: json['poster'] as String? ?? json['image'] as String?,
    keyword: json['keyword'] as String?,
    // rss_sites 和 search_sites 可能是 List 或 String
    sites: _parseSites(json['rss_sites']) ?? _parseSites(json['search_sites']),
    filterRule: json['filter_rule'] is int ? json['filter_rule'] as int : int.tryParse(json['filter_rule']?.toString() ?? ''),
    totalEp: json['total_ep'] is int ? json['total_ep'] as int : int.tryParse(json['total_ep']?.toString() ?? ''),
    currentEp: json['current_ep'] is int ? json['current_ep'] as int : int.tryParse(json['current_ep']?.toString() ?? ''),
  );

  // 将 sites 字段（可能是 List 或 String）转换为字符串
  static String? _parseSites(dynamic value) {
    if (value == null) return null;
    if (value is String) return value.isNotEmpty ? value : null;
    if (value is List) return value.isNotEmpty ? value.join(',') : null;
    return value.toString();
  }

  final int id;
  final String name;
  final String type;
  final String? tmdbId;
  final String? year;
  final int? season;
  final String? state;
  final String? posterPath;
  final String? keyword;
  final String? sites;
  final int? filterRule;
  final int? totalEp;
  final int? currentEp;

  bool get isMovie => type.toUpperCase() == 'MOV';
  bool get isTv => type.toUpperCase() == 'TV';

  /// 订阅进度 (0.0 - 1.0)
  double? get progress {
    if (isMovie || totalEp == null || totalEp == 0) return null;
    return (currentEp ?? 0) / totalEp!;
  }

  /// 季度显示文本
  String? get seasonDisplay {
    if (isMovie || season == null) return null;
    return appL10n.ntSubscribeSeasonDisplay(season ?? 0);
  }

  /// 是否已完成
  bool get isCompleted {
    if (isMovie) return state == 'D' || state == 'R';
    if (totalEp == null) return false;
    return (currentEp ?? 0) >= totalEp!;
  }

  /// 简介（占位用）
  String? get overview => keyword;
}

/// 订阅历史
class NtSubscribeHistory {
  const NtSubscribeHistory({
    required this.id,
    required this.name,
    required this.type,
    this.tmdbId,
    this.year,
    this.season,
    this.posterPath,
    this.addTime,
  });

  factory NtSubscribeHistory.fromJson(Map<String, dynamic> json) => NtSubscribeHistory(
    id: json['id'] as int? ?? json['rssid'] as int? ?? 0,
    name: json['name'] as String? ?? json['title'] as String? ?? '',
    type: json['type'] as String? ?? 'MOV',
    tmdbId: json['tmdbid']?.toString(),
    year: json['year']?.toString(),
    season: json['season'] as int?,
    posterPath: json['poster'] as String? ?? json['image'] as String?,
    addTime: json['add_time'] != null
        ? DateTime.tryParse(json['add_time'] as String)
        : null,
  );

  final int id;
  final String name;
  final String type;
  final String? tmdbId;
  final String? year;
  final int? season;
  final String? posterPath;
  final DateTime? addTime;
}
