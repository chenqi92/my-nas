/// 识别词相关数据模型
library;

import 'package:my_nas/core/i18n/app_l10n.dart';

/// 识别词组
class NtWordsGroup {
  const NtWordsGroup({
    required this.id,
    this.tmdbId,
    this.tmdbType,
    this.title,
    this.year,
    this.words,
  });

  factory NtWordsGroup.fromJson(Map<String, dynamic> json) => NtWordsGroup(
        id: json['id'] as int? ?? json['gid'] as int? ?? 0,
        tmdbId: json['tmdb_id'] as String?,
        tmdbType: json['tmdb_type'] as String?,
        title: json['title'] as String?,
        year: json['year'] as String?,
        words: (json['words'] as List?)
            ?.map((e) => NtWordItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final int id;
  final String? tmdbId;
  final String? tmdbType;
  final String? title;
  final String? year;
  final List<NtWordItem>? words;

  /// 是否为电影
  bool get isMovie => tmdbType == 'movie';

  /// 是否为电视剧
  bool get isTv => tmdbType == 'tv';
}

/// 识别词
class NtWordItem {
  const NtWordItem({
    required this.id,
    this.groupId,
    this.replaced,
    this.replace,
    this.front,
    this.back,
    this.offset,
    this.type,
    this.season,
    this.enabled,
    this.regex,
    this.help,
  });

  factory NtWordItem.fromJson(Map<String, dynamic> json) => NtWordItem(
        id: json['id'] as int? ?? json['wid'] as int? ?? 0,
        groupId: json['group_id'] as int?,
        replaced: json['replaced'] as String?,
        replace: json['replace'] as String?,
        front: json['front'] as String?,
        back: json['back'] as String?,
        offset: json['offset'] as String?,
        type: json['type'] as int?,
        season: json['season'] as int?,
        enabled: json['enabled'] as int?,
        regex: json['regex'] as int?,
        help: json['help'] as String?,
      );

  final int id;
  final int? groupId;
  final String? replaced;
  final String? replace;
  final String? front;
  final String? back;
  final String? offset;
  final int? type;
  final int? season;
  final int? enabled;
  final int? regex;
  final String? help;

  /// 是否启用
  bool get isEnabled => enabled == 1;

  /// 是否为正则
  bool get isRegex => regex == 1;

  /// 类型描述
  String get typeText => switch (type) {
        1 => appL10n.nastoolWordBlock,
        2 => appL10n.nastoolWordReplace,
        3 => appL10n.nastoolWordEpisodeOffset,
        4 => appL10n.nastoolWordBeforeRecognition,
        5 => appL10n.nastoolWordAfterRecognition,
        _ => appL10n.nastoolUnknown,
      };
}

/// 识别词分析结果
class NtWordAnalyse {
  const NtWordAnalyse({
    this.note,
    this.ids,
    this.groups,
  });

  factory NtWordAnalyse.fromJson(Map<String, dynamic> json) => NtWordAnalyse(
        note: json['note'] as String?,
        ids: (json['ids'] as List?)?.cast<int>(),
        groups: (json['groups'] as List?)
            ?.map((e) => NtWordsGroup.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final String? note;
  final List<int>? ids;
  final List<NtWordsGroup>? groups;
}
