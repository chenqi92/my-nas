import 'package:uuid/uuid.dart';

/// 单端点配置：一次 HTTP 请求 + 一段解析脚本。
///
/// `url`、`bodyTemplate`、`params`、`headers` 中可以使用 `{{name}}` 占位符；
/// 引擎按调用上下文（query / artist / id 等）替换。
///
/// `script` 是一段函数体 JS，运行时引擎会包成
/// `(function(response, args){ <script> })(<resp>, <args>)`，
/// 期望返回值结构由调用方决定（搜索返回数组、详情返回对象、歌词返回 `{ lrcContent, wordLevelLrc }` 等）。
class EndpointConfig {
  EndpointConfig({
    required this.url,
    this.method = 'GET',
    this.params,
    this.headers,
    this.bodyTemplate,
    this.script = '',
  });

  factory EndpointConfig.fromJson(Map<String, dynamic> json) => EndpointConfig(
        url: json['url'] as String? ?? '',
        method: (json['method'] as String? ?? 'GET').toUpperCase(),
        params: _stringMapOrNull(json['params']),
        headers: _stringMapOrNull(json['headers']),
        bodyTemplate: json['bodyTemplate'] as String?,
        script: json['script'] as String? ?? '',
      );

  final String url;
  final String method;
  final Map<String, String>? params;
  final Map<String, String>? headers;
  final String? bodyTemplate;
  final String script;

  Map<String, dynamic> toJson() => {
        'url': url,
        'method': method,
        if (params != null) 'params': params,
        if (headers != null) 'headers': headers,
        if (bodyTemplate != null) 'bodyTemplate': bodyTemplate,
        'script': script,
      };
}

Map<String, String>? _stringMapOrNull(dynamic v) {
  if (v is! Map) return null;
  return v.map((k, value) => MapEntry(k.toString(), value.toString()));
}

/// 用户导入的音乐元数据源配置。schema 与社区通用 JSON 模板对齐：
/// 顶层若干元数据 + 4 个可选 endpoint（search/detail/cover/lyrics）+ capabilities。
///
/// 本应用 **不内嵌任何源**；启动时只从 Hive 读用户主动导入的内容。
class ScraperConfig {
  ScraperConfig({
    String? id,
    required this.name,
    this.version = 1,
    this.icon,
    this.color,
    this.rateLimit,
    this.headers,
    this.capabilities = const [],
    this.sslTrustDomains,
    this.cookie,
    this.search,
    this.detail,
    this.cover,
    this.lyrics,
    this.secrets,
    this.modifiedAt,
    this.isDeleted,
    this.deletedAt,
    this.enabled = true,
    this.customOrder = 0,
  }) : id = id ?? const Uuid().v4();

  factory ScraperConfig.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    int? parseIntOrNull(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    bool? parseBoolOrNull(dynamic v) {
      if (v is bool) return v;
      if (v is int) return v != 0;
      if (v is String) {
        final lower = v.toLowerCase();
        if (lower == 'true' || lower == '1') return true;
        if (lower == 'false' || lower == '0') return false;
      }
      return null;
    }

    EndpointConfig? readEndpoint(dynamic v) {
      if (v is! Map) return null;
      return EndpointConfig.fromJson(Map<String, dynamic>.from(v));
    }

    final caps = (json['capabilities'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];

    final ssl =
        (json['sslTrustDomains'] as List?)?.map((e) => e.toString()).toList();

    return ScraperConfig(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      version: parseIntOrNull(json['version']) ?? 1,
      icon: json['icon'] as String?,
      color: json['color'] as String?,
      rateLimit: parseIntOrNull(json['rateLimit']),
      headers: _stringMapOrNull(json['headers']),
      capabilities: caps,
      sslTrustDomains: ssl,
      cookie: json['cookie'] as String?,
      search: readEndpoint(json['search']),
      detail: readEndpoint(json['detail']),
      cover: readEndpoint(json['cover']),
      lyrics: readEndpoint(json['lyrics']),
      secrets: _stringMapOrNull(json['secrets']),
      modifiedAt: parseDate(json['modifiedAt']),
      isDeleted: parseBoolOrNull(json['isDeleted']),
      deletedAt: parseDate(json['deletedAt']),
      enabled: parseBoolOrNull(json['__enabled']) ?? true,
      customOrder: parseIntOrNull(json['__customOrder']) ?? 0,
    );
  }

  final String id;
  String name;
  int version;
  String? icon;
  String? color;
  int? rateLimit;
  Map<String, String>? headers;
  List<String> capabilities;
  List<String>? sslTrustDomains;
  String? cookie;
  EndpointConfig? search;
  EndpointConfig? detail;
  EndpointConfig? cover;
  EndpointConfig? lyrics;
  Map<String, String>? secrets;
  DateTime? modifiedAt;
  bool? isDeleted;
  DateTime? deletedAt;

  // 应用本地状态（不写入对外导出的 JSON 顶层字段，前缀 __ 区分）
  bool enabled;
  int customOrder;

  String get displayName => name.isEmpty ? id : name;

  bool hasCapability(String cap) => capabilities.contains(cap);

  /// 用于内部存储 / 跨设备同步的完整序列化（包含本地状态）。
  Map<String, dynamic> toJson({bool includeSecrets = true}) => {
        'id': id,
        'name': name,
        'version': version,
        if (icon != null) 'icon': icon,
        if (color != null) 'color': color,
        if (rateLimit != null) 'rateLimit': rateLimit,
        if (headers != null) 'headers': headers,
        'capabilities': capabilities,
        if (sslTrustDomains != null) 'sslTrustDomains': sslTrustDomains,
        if (cookie != null) 'cookie': cookie,
        if (search != null) 'search': search!.toJson(),
        if (detail != null) 'detail': detail!.toJson(),
        if (cover != null) 'cover': cover!.toJson(),
        if (lyrics != null) 'lyrics': lyrics!.toJson(),
        if (includeSecrets && secrets != null) 'secrets': secrets,
        if (modifiedAt != null)
          'modifiedAt': modifiedAt!.toUtc().toIso8601String(),
        if (isDeleted != null) 'isDeleted': isDeleted,
        if (deletedAt != null)
          'deletedAt': deletedAt!.toUtc().toIso8601String(),
        '__enabled': enabled,
        '__customOrder': customOrder,
      };

  /// 对外分享时移除 secrets / 本地状态 / 时间戳，得到「可分享」的快照。
  Map<String, dynamic> toShareJson() {
    final m = toJson(includeSecrets: false)
      ..remove('__enabled')
      ..remove('__customOrder')
      ..remove('modifiedAt')
      ..remove('isDeleted')
      ..remove('deletedAt');
    return m;
  }

  ScraperConfig copyWith({
    String? id,
    String? name,
    int? version,
    String? icon,
    String? color,
    int? rateLimit,
    Map<String, String>? headers,
    List<String>? capabilities,
    List<String>? sslTrustDomains,
    String? cookie,
    EndpointConfig? search,
    EndpointConfig? detail,
    EndpointConfig? cover,
    EndpointConfig? lyrics,
    Map<String, String>? secrets,
    DateTime? modifiedAt,
    bool? isDeleted,
    DateTime? deletedAt,
    bool? enabled,
    int? customOrder,
  }) =>
      ScraperConfig(
        id: id ?? this.id,
        name: name ?? this.name,
        version: version ?? this.version,
        icon: icon ?? this.icon,
        color: color ?? this.color,
        rateLimit: rateLimit ?? this.rateLimit,
        headers: headers ?? this.headers,
        capabilities: capabilities ?? this.capabilities,
        sslTrustDomains: sslTrustDomains ?? this.sslTrustDomains,
        cookie: cookie ?? this.cookie,
        search: search ?? this.search,
        detail: detail ?? this.detail,
        cover: cover ?? this.cover,
        lyrics: lyrics ?? this.lyrics,
        secrets: secrets ?? this.secrets,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        isDeleted: isDeleted ?? this.isDeleted,
        deletedAt: deletedAt ?? this.deletedAt,
        enabled: enabled ?? this.enabled,
        customOrder: customOrder ?? this.customOrder,
      );
}

/// 标准 capability 常量（不强制约束，用户 JSON 可写其它字符串）。
class ScraperCapability {
  static const String metadata = 'metadata';
  static const String cover = 'cover';
  static const String lyrics = 'lyrics';
  static const String lyricsWordLevel = 'lyricsWordLevel';
}
