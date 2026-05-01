import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

/// 法律/合规风险等级
enum MusicScraperRiskLevel {
  /// 开放数据库，明确许可使用
  open,

  /// 使用未公开/逆向工程的 API，违反平台 ToS，但不绕过技术保护措施
  tosViolation,

  /// 主动绕过加密/签名等技术保护措施，存在不正当竞争争议
  antiCircumvention,
}

/// 音乐刮削源类型
enum MusicScraperType {
  musicBrainz('MusicBrainz', 'musicbrainz'),
  acoustId('AcoustID', 'acoustid'),
  neteaseMusic('网易云音乐', 'netease'),
  qqMusic('QQ音乐', 'qqmusic'),
  kugouMusic('酷狗音乐', 'kugou'),
  kuwoMusic('酷我音乐', 'kuwo'),
  miguMusic('咪咕音乐', 'migu'),
  musicTagWeb('Music Tag Web', 'musictagweb');

  const MusicScraperType(this.displayName, this.id);

  /// 显示名称
  final String displayName;

  /// 唯一标识符
  final String id;

  /// 图标
  IconData get icon => switch (this) {
        MusicScraperType.musicBrainz => Icons.album_rounded,
        MusicScraperType.acoustId => Icons.fingerprint_rounded,
        MusicScraperType.neteaseMusic => Icons.cloud_rounded,
        MusicScraperType.qqMusic => Icons.music_note_rounded,
        MusicScraperType.kugouMusic => Icons.graphic_eq_rounded,
        MusicScraperType.kuwoMusic => Icons.headphones_rounded,
        MusicScraperType.miguMusic => Icons.library_music_rounded,
        MusicScraperType.musicTagWeb => Icons.dns_rounded,
      };

  /// 主题色
  Color get themeColor => switch (this) {
        MusicScraperType.musicBrainz => const Color(0xFFBA478F), // MusicBrainz purple
        MusicScraperType.acoustId => const Color(0xFF5BC0DE), // AcoustID blue
        MusicScraperType.neteaseMusic => const Color(0xFFE60026), // 网易云红
        MusicScraperType.qqMusic => const Color(0xFF31C27C), // QQ音乐绿
        MusicScraperType.kugouMusic => const Color(0xFF2196F3), // 酷狗蓝
        MusicScraperType.kuwoMusic => const Color(0xFFFF6600), // 酷我橙
        MusicScraperType.miguMusic => const Color(0xFFFF0653), // 咪咕红
        MusicScraperType.musicTagWeb => const Color(0xFF6366F1), // Indigo
      };

  /// 描述
  String get description => switch (this) {
        MusicScraperType.musicBrainz => '开放音乐数据库，支持元数据和封面查询',
        MusicScraperType.acoustId => '声纹识别服务，需要 API Key',
        MusicScraperType.neteaseMusic => '国内音乐平台，支持歌词和封面',
        MusicScraperType.qqMusic => '国内音乐平台，支持歌词和封面',
        MusicScraperType.kugouMusic => '国内音乐平台，歌词库丰富',
        MusicScraperType.kuwoMusic => '国内音乐平台，支持歌词和封面',
        MusicScraperType.miguMusic => '中国移动旗下音乐平台，无损音源丰富',
        MusicScraperType.musicTagWeb => '自托管音乐刮削服务，需配置服务器地址',
      };

  /// 是否支持元数据
  bool get supportsMetadata => [
        MusicScraperType.musicBrainz,
        MusicScraperType.neteaseMusic,
        MusicScraperType.qqMusic,
        MusicScraperType.kugouMusic,
        MusicScraperType.kuwoMusic,
        MusicScraperType.miguMusic,
        MusicScraperType.musicTagWeb,
      ].contains(this);

  /// 是否支持封面
  bool get supportsCover => [
        MusicScraperType.musicBrainz,
        MusicScraperType.neteaseMusic,
        MusicScraperType.qqMusic,
        MusicScraperType.kugouMusic,
        MusicScraperType.kuwoMusic,
        MusicScraperType.miguMusic,
        MusicScraperType.musicTagWeb,
      ].contains(this);

  /// 是否支持歌词
  bool get supportsLyrics => [
        MusicScraperType.neteaseMusic,
        MusicScraperType.qqMusic,
        MusicScraperType.kugouMusic,
        MusicScraperType.kuwoMusic,
        MusicScraperType.miguMusic,
        MusicScraperType.musicTagWeb,
      ].contains(this);

  /// 是否支持声纹识别
  bool get supportsFingerprint => this == MusicScraperType.acoustId;

  /// 是否需要 API Key
  bool get requiresApiKey => [
        MusicScraperType.acoustId,
      ].contains(this);

  /// 是否需要 Cookie（可选）
  bool get supportsCookie => [
        MusicScraperType.neteaseMusic,
        MusicScraperType.qqMusic,
      ].contains(this);

  /// 是否需要服务器地址
  bool get requiresServerUrl => this == MusicScraperType.musicTagWeb;

  /// 法律/合规风险等级
  MusicScraperRiskLevel get riskLevel => switch (this) {
        MusicScraperType.musicBrainz => MusicScraperRiskLevel.open,
        MusicScraperType.acoustId => MusicScraperRiskLevel.open,
        MusicScraperType.neteaseMusic => MusicScraperRiskLevel.antiCircumvention,
        MusicScraperType.qqMusic => MusicScraperRiskLevel.tosViolation,
        MusicScraperType.kugouMusic => MusicScraperRiskLevel.tosViolation,
        MusicScraperType.kuwoMusic => MusicScraperRiskLevel.tosViolation,
        MusicScraperType.miguMusic => MusicScraperRiskLevel.tosViolation,
        // MusicTagWeb 转发到自托管服务，风险由用户部署决定，按 ToS 违反等级提示
        MusicScraperType.musicTagWeb => MusicScraperRiskLevel.tosViolation,
      };

  /// 风险提示文案（启用前向用户展示）
  String? get riskNotice => switch (riskLevel) {
        MusicScraperRiskLevel.open => null,
        MusicScraperRiskLevel.tosViolation =>
            '该刮削源使用未公开 API，可能违反平台服务条款。仅获取公开元数据/封面/歌词写入你本地的音频文件； '
                '请仅用于管理你合法获取的音乐，并自行承担合规责任。',
        MusicScraperRiskLevel.antiCircumvention =>
            '该刮削源通过加密请求绕过平台限制，存在不正当竞争争议（参见网易诉酷我案等先例）。 '
                '建议优先使用开放数据源（MusicBrainz / AcoustID）。如需启用，请仅用于管理你合法获取的音乐，并自行承担合规责任。',
      };

  /// 是否需要在启用前显式确认（高风险源）
  bool get requiresRiskAcknowledgement =>
      riskLevel != MusicScraperRiskLevel.open;

  /// 从 id 获取类型
  static MusicScraperType fromId(String id) => MusicScraperType.values.firstWhere(
        (t) => t.id == id,
        orElse: () => MusicScraperType.musicBrainz,
      );
}

/// 音乐刮削源实体
class MusicScraperSourceEntity {
  MusicScraperSourceEntity({
    String? id,
    required this.name,
    required this.type,
    this.isEnabled = true,
    this.priority = 0,
    this.apiKey,
    this.cookie,
    this.extraConfig,
  })  : id = id ?? const Uuid().v4();

  factory MusicScraperSourceEntity.fromJson(Map<String, dynamic> json) =>
      MusicScraperSourceEntity(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        type: MusicScraperType.fromId(json['type'] as String? ?? 'musicbrainz'),
        isEnabled: json['isEnabled'] as bool? ?? true,
        priority: json['priority'] as int? ?? 0,
        apiKey: json['apiKey'] as String?,
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
  final MusicScraperType type;

  /// 是否启用
  final bool isEnabled;

  /// 优先级（数值越小优先级越高）
  final int priority;

  /// API Key
  final String? apiKey;

  /// Cookie（网易云、QQ音乐可选）
  final String? cookie;

  /// 额外配置
  final Map<String, dynamic>? extraConfig;

  /// 获取显示名称
  String get displayName => name.isNotEmpty ? name : type.displayName;

  /// 是否已配置（有必要的凭证）
  bool get isConfigured => switch (type) {
        MusicScraperType.musicBrainz => true, // 无需认证
        MusicScraperType.acoustId => apiKey != null && apiKey!.isNotEmpty,
        MusicScraperType.neteaseMusic => true, // Cookie 可选
        MusicScraperType.qqMusic => true, // Cookie 可选
        MusicScraperType.kugouMusic => true, // 无需认证
        MusicScraperType.kuwoMusic => true, // 无需认证
        MusicScraperType.miguMusic => true, // 无需认证
        MusicScraperType.musicTagWeb => _isMusicTagWebConfigured,
      };

  /// Music Tag Web 是否已配置
  bool get _isMusicTagWebConfigured {
    final serverUrl = extraConfig?['serverUrl'] as String?;
    return serverUrl != null && serverUrl.isNotEmpty;
  }

  /// 获取 Music Tag Web 服务器地址
  String? get serverUrl => extraConfig?['serverUrl'] as String?;

  /// 获取请求间隔（秒）
  int get requestInterval =>
      extraConfig?['requestInterval'] as int? ??
      switch (type) {
        MusicScraperType.musicBrainz => 1, // MusicBrainz 要求 1 秒间隔
        MusicScraperType.neteaseMusic => 1,
        MusicScraperType.qqMusic => 1,
        _ => 0,
      };

  MusicScraperSourceEntity copyWith({
    String? id,
    String? name,
    MusicScraperType? type,
    bool? isEnabled,
    int? priority,
    String? apiKey,
    String? cookie,
    Map<String, dynamic>? extraConfig,
  }) =>
      MusicScraperSourceEntity(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        isEnabled: isEnabled ?? this.isEnabled,
        priority: priority ?? this.priority,
        apiKey: apiKey ?? this.apiKey,
        cookie: cookie ?? this.cookie,
        extraConfig: extraConfig ?? this.extraConfig,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.id,
        'isEnabled': isEnabled,
        'priority': priority,
        'apiKey': apiKey,
        'cookie': cookie,
        'extraConfig': extraConfig,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MusicScraperSourceEntity &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 音乐刮削凭证
///
/// 所有敏感字段（apiKey / cookie / password）落地到 flutter_secure_storage，
/// 不会进入 Hive 配置文件。其它字段（serverUrl / username / preferredSource 等）
/// 仍保留在 [MusicScraperSourceEntity.extraConfig] 中。
class MusicScraperCredential {
  const MusicScraperCredential({
    this.apiKey,
    this.cookie,
    this.password,
  });

  factory MusicScraperCredential.fromJson(Map<String, dynamic> json) =>
      MusicScraperCredential(
        apiKey: json['apiKey'] as String?,
        cookie: json['cookie'] as String?,
        password: json['password'] as String?,
      );

  final String? apiKey;
  final String? cookie;

  /// Music Tag Web 等需要密码的源使用
  final String? password;

  bool get isEmpty =>
      (apiKey == null || apiKey!.isEmpty) &&
      (cookie == null || cookie!.isEmpty) &&
      (password == null || password!.isEmpty);

  Map<String, dynamic> toJson() => {
        'apiKey': apiKey,
        'cookie': cookie,
        'password': password,
      };
}
