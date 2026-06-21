import 'package:flutter/material.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:uuid/uuid.dart';

/// 刮削源类型
enum ScraperType {
  tmdb('TMDB', 'tmdb'),
  doubanApi('豆瓣 API', 'douban_api'),
  doubanWeb('豆瓣网页', 'douban_web');

  const ScraperType(this.displayName, this.id);

  /// 显示名称
  final String displayName;

  /// 唯一标识符
  final String id;

  /// 图标
  IconData get icon => switch (this) {
        ScraperType.tmdb => Icons.movie_filter_rounded,
        ScraperType.doubanApi => Icons.api_rounded,
        ScraperType.doubanWeb => Icons.web_rounded,
      };

  /// 主题色
  Color get themeColor => switch (this) {
        ScraperType.tmdb => const Color(0xFF01D277), // TMDB green
        ScraperType.doubanApi => const Color(0xFF007722), // 豆瓣绿
        ScraperType.doubanWeb => const Color(0xFF2D963D), // 豆瓣绿变体
      };

  /// 描述
  String get description => switch (this) {
        ScraperType.tmdb => appL10n.scraperTypeDescTmdb,
        ScraperType.doubanApi => appL10n.scraperTypeDescDoubanApi,
        ScraperType.doubanWeb => appL10n.scraperTypeDescDoubanWeb,
      };

  /// 是否需要 API Key
  bool get requiresApiKey => switch (this) {
        ScraperType.tmdb => true,
        ScraperType.doubanApi => false, // 可选
        ScraperType.doubanWeb => false,
      };

  /// 是否需要 API URL
  bool get requiresApiUrl => switch (this) {
        ScraperType.doubanApi => true,
        _ => false,
      };

  /// 是否需要 Cookie
  bool get requiresCookie => switch (this) {
        ScraperType.doubanWeb => true,
        _ => false,
      };

  /// 从 id 获取类型
  static ScraperType fromId(String id) => ScraperType.values.firstWhere(
        (t) => t.id == id,
        orElse: () => ScraperType.tmdb,
      );
}

/// 刮削源实体
class ScraperSourceEntity {
  ScraperSourceEntity({
    String? id,
    required this.name,
    required this.type,
    this.isEnabled = true,
    this.priority = 0,
    this.apiKey,
    this.apiUrl,
    this.cookie,
    int requestInterval = 0,
    Map<String, dynamic>? extraConfig,
  })  : id = id ?? const Uuid().v4(),
        extraConfig = extraConfig ?? (requestInterval > 0 ? {'requestInterval': requestInterval} : null);

  factory ScraperSourceEntity.fromJson(Map<String, dynamic> json) =>
      ScraperSourceEntity(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        type: ScraperType.fromId(json['type'] as String? ?? 'tmdb'),
        isEnabled: json['isEnabled'] as bool? ?? true,
        priority: json['priority'] as int? ?? 0,
        apiKey: json['apiKey'] as String?,
        apiUrl: json['apiUrl'] as String?,
        cookie: json['cookie'] as String?,
        extraConfig: json['extraConfig'] != null
            ? Map<String, dynamic>.from(json['extraConfig'] as Map)
            : null,
      );

  /// 唯一标识符
  final String id;

  /// 显示名称
  final String name;

  /// 刮削源类型
  final ScraperType type;

  /// 是否启用
  final bool isEnabled;

  /// 优先级（数值越小优先级越高）
  final int priority;

  /// API Key（TMDB、部分豆瓣 API 需要）
  final String? apiKey;

  /// API 地址（豆瓣第三方 API）
  final String? apiUrl;

  /// Cookie（豆瓣网页爬虫）
  final String? cookie;

  /// 额外配置
  final Map<String, dynamic>? extraConfig;

  /// 获取显示名称
  String get displayName => name.isNotEmpty ? name : type.displayName;

  /// 是否已配置（有必要的凭证）
  bool get isConfigured => switch (type) {
        ScraperType.tmdb => apiKey != null && apiKey!.isNotEmpty,
        ScraperType.doubanApi => apiUrl != null && apiUrl!.isNotEmpty,
        ScraperType.doubanWeb => cookie != null && cookie!.isNotEmpty,
      };

  /// 获取请求间隔（秒）
  int get requestInterval =>
      extraConfig?['requestInterval'] as int? ??
      switch (type) {
        ScraperType.doubanWeb => 3, // 豆瓣网页默认 3 秒间隔
        _ => 0,
      };

  ScraperSourceEntity copyWith({
    String? id,
    String? name,
    ScraperType? type,
    bool? isEnabled,
    int? priority,
    String? apiKey,
    String? apiUrl,
    String? cookie,
    int? requestInterval,
    Map<String, dynamic>? extraConfig,
  }) {
    // 处理 requestInterval
    var finalExtraConfig = extraConfig ?? this.extraConfig;
    if (requestInterval != null) {
      finalExtraConfig = {...?finalExtraConfig, 'requestInterval': requestInterval};
    }

    return ScraperSourceEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      isEnabled: isEnabled ?? this.isEnabled,
      priority: priority ?? this.priority,
      apiKey: apiKey ?? this.apiKey,
      apiUrl: apiUrl ?? this.apiUrl,
      cookie: cookie ?? this.cookie,
      extraConfig: finalExtraConfig,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.id,
        'isEnabled': isEnabled,
        'priority': priority,
        'apiKey': apiKey,
        'apiUrl': apiUrl,
        'cookie': cookie,
        'extraConfig': extraConfig,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScraperSourceEntity &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 刮削凭证
class ScraperCredential {
  const ScraperCredential({
    this.apiKey,
    this.cookie,
  });

  factory ScraperCredential.fromJson(Map<String, dynamic> json) =>
      ScraperCredential(
        apiKey: json['apiKey'] as String?,
        cookie: json['cookie'] as String?,
      );

  final String? apiKey;
  final String? cookie;

  bool get isEmpty => (apiKey == null || apiKey!.isEmpty) &&
      (cookie == null || cookie!.isEmpty);

  Map<String, dynamic> toJson() => {
        'apiKey': apiKey,
        'cookie': cookie,
      };
}
