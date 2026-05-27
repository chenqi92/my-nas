import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';

/// DNS over HTTPS (DoH) 提供商
enum DohProvider {
  cloudflare(
    'Cloudflare',
    'https://cloudflare-dns.com/dns-query',
    ['1.1.1.1', '1.0.0.1'],
  ),
  google(
    'Google',
    'https://dns.google/resolve',
    ['8.8.8.8', '8.8.4.4'],
  ),
  alidns(
    '阿里 DNS',
    'https://dns.alidns.com/resolve',
    ['223.5.5.5', '223.6.6.6'],
  ),
  dnspod(
    'DNSPod',
    'https://doh.pub/dns-query',
    [], // doh.pub 没有公开静态 IP，依赖系统解析
  );

  const DohProvider(this.displayName, this.endpoint, this.bootstrapIps);

  final String displayName;
  final String endpoint;

  /// DoH 端点本身的已知 IP（避免 DoH 端点也被污染）
  final List<String> bootstrapIps;
}

/// 通过 DoH（DNS over HTTPS）解析域名
///
/// 用法：
/// ```dart
/// final ip = await DohResolver.resolve('api.themoviedb.org');
/// final batch = await DohResolver.resolveAll(['a.com', 'b.com']);
/// ```
class DohResolver {
  DohResolver._();

  /// 单次请求超时
  static const Duration _timeout = Duration(seconds: 8);

  /// 常用域名清单 —— 一键解析按钮会跑这些
  static const List<String> commonHosts = [
    'api.themoviedb.org',
    'api.tmdb.org',
    'image.tmdb.org',
    'www.themoviedb.org',
  ];

  /// 解析单个域名为 IPv4 字符串；失败返回 null
  static Future<String?> resolve(
    String host, {
    DohProvider provider = DohProvider.cloudflare,
  }) async {
    try {
      final ips = await _query(host, type: 'A', provider: provider);
      return ips.isEmpty ? null : ips.first;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'DoH 解析失败: $host (${provider.name})');
      return null;
    }
  }

  /// 批量解析；返回 host → ip 的 map（失败的 host 不出现在结果中）
  static Future<Map<String, String>> resolveAll(
    Iterable<String> hosts, {
    DohProvider provider = DohProvider.cloudflare,
  }) async {
    final entries = await Future.wait(
      hosts.map((h) async {
        final ip = await resolve(h, provider: provider);
        return ip == null ? null : MapEntry(h, ip);
      }),
    );
    return Map.fromEntries(entries.whereType<MapEntry<String, String>>());
  }

  /// 发起一次 DoH 查询，返回所有 A/AAAA 记录的 IP
  static Future<List<String>> _query(
    String host, {
    required String type,
    required DohProvider provider,
  }) async {
    final uri = Uri.parse(provider.endpoint).replace(queryParameters: {
      'name': host,
      'type': type,
    });

    final response = await _httpFor(provider).get(
      uri,
      headers: const {'Accept': 'application/dns-json'},
    ).timeout(_timeout);

    if (response.statusCode != 200) {
      logger.w('DoH ${provider.name} ${response.statusCode}: $host');
      return const [];
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final answers = data['Answer'] as List? ?? const [];
    final ips = <String>[];
    for (final ans in answers) {
      if (ans is Map) {
        // type 1 = A, type 28 = AAAA
        final t = ans['type'] as int? ?? 0;
        if (t == 1 || t == 28) {
          final v = ans['data'] as String?;
          if (v != null && v.isNotEmpty) ips.add(v);
        }
      }
    }
    return ips;
  }

  /// 每个 provider 用独立 client，让 connectionFactory 把 DoH 端点本身的域名
  /// 解析到 bootstrap IP，避免「DoH 端点也被污染」死循环。
  static final Map<DohProvider, http.Client> _clientCache = {};

  static http.Client _httpFor(DohProvider provider) =>
      _clientCache.putIfAbsent(provider, () => _buildClient(provider));

  static http.Client _buildClient(DohProvider provider) {
    final httpClient = HttpClient();
    final bootstrap = provider.bootstrapIps;
    if (bootstrap.isNotEmpty) {
      httpClient.connectionFactory = (uri, proxyHost, proxyPort) {
        if (proxyHost != null && proxyPort != null) {
          return Socket.startConnect(proxyHost, proxyPort);
        }
        // 把 DoH 域名替换为 bootstrap IP；SNI/证书仍按原域名校验
        final targetHost = bootstrap.first;
        return Socket.startConnect(targetHost, uri.port);
      };
    }
    return IOClient(httpClient);
  }
}
