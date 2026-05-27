/// 域名 → IP 映射条目
///
/// 类似系统 hosts 文件的一行：把 [host] 解析为 [ip]，但保留原域名用于
/// HTTPS 的 SNI 和证书校验。
class HostMappingEntry {
  HostMappingEntry({
    required this.host,
    required this.ip,
    this.enabled = true,
    this.source = HostMappingSource.manual,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  factory HostMappingEntry.fromJson(Map<String, dynamic> json) => HostMappingEntry(
        host: json['host'] as String,
        ip: json['ip'] as String,
        enabled: json['enabled'] as bool? ?? true,
        source: HostMappingSource.values.firstWhere(
          (e) => e.name == (json['source'] as String? ?? 'manual'),
          orElse: () => HostMappingSource.manual,
        ),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );

  /// 域名（不含协议和端口），如 `api.themoviedb.org`
  final String host;

  /// 解析后的 IP 地址（IPv4 或 IPv6）
  final String ip;

  /// 是否启用（禁用后 resolve 时跳过此条）
  final bool enabled;

  /// 来源：用户手填 / DoH 自动解析
  final HostMappingSource source;

  /// 最近更新时间（用于显示 + DoH 缓存判断）
  final DateTime updatedAt;

  HostMappingEntry copyWith({
    String? host,
    String? ip,
    bool? enabled,
    HostMappingSource? source,
    DateTime? updatedAt,
  }) =>
      HostMappingEntry(
        host: host ?? this.host,
        ip: ip ?? this.ip,
        enabled: enabled ?? this.enabled,
        source: source ?? this.source,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'host': host,
        'ip': ip,
        'enabled': enabled,
        'source': source.name,
        'updatedAt': updatedAt.toIso8601String(),
      };
}

enum HostMappingSource {
  /// 用户手动填写
  manual,

  /// DoH 自动解析得到
  doh,
}
