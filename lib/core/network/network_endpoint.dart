/// Canonical endpoint builder shared by connection sources.
///
/// It accepts a bare hostname, IPv4/IPv6 address, or a full URL. Explicit URL
/// components win over form defaults, while [basePath] is appended without
/// duplicating an identical suffix.
class NetworkEndpoint {
  const NetworkEndpoint._();

  static Uri resolve({
    required String host,
    required int port,
    required bool useSsl,
    String? basePath,
  }) {
    final defaultScheme = useSsl ? 'https' : 'http';
    final raw = host.trim();
    final hasExplicitScheme = raw.contains('://');

    Uri? parsed;
    if (hasExplicitScheme) {
      parsed = Uri.tryParse(raw);
    } else if (raw.contains('/') || _looksLikeHostWithPort(raw)) {
      parsed = Uri.tryParse('$defaultScheme://$raw');
    }

    final scheme = parsed?.hasScheme == true ? parsed!.scheme : defaultScheme;
    var effectiveHost = parsed?.host.isNotEmpty == true ? parsed!.host : raw;
    if (effectiveHost.startsWith('[') && effectiveHost.endsWith(']')) {
      effectiveHost = effectiveHost.substring(1, effectiveHost.length - 1);
    }
    final effectivePort = parsed?.hasPort == true
        ? parsed!.port
        : hasExplicitScheme
        ? (scheme == 'https' ? 443 : 80)
        : port;
    final path = _mergePaths(parsed?.path, basePath);

    return Uri(
      scheme: scheme,
      host: effectiveHost,
      port: effectivePort,
      path: path.isEmpty ? null : path,
    );
  }

  static String buildBaseUrl({
    required String host,
    required int port,
    required bool useSsl,
    String? basePath,
  }) => resolve(
    host: host,
    port: port,
    useSsl: useSsl,
    basePath: basePath,
  ).toString().replaceFirst(RegExp(r'/$'), '');

  static bool _looksLikeHostWithPort(String value) {
    if (value.startsWith('[')) return value.contains(']:');
    // A single colon is host:port; multiple colons are a bare IPv6 address.
    return ':'.allMatches(value).length == 1;
  }

  static String _mergePaths(String? first, String? second) {
    final segments = <String>[];
    for (final value in [first, second]) {
      if (value == null || value.trim().isEmpty || value.trim() == '/') {
        continue;
      }
      final normalized = value.trim().replaceAll(RegExp(r'^/+|/+$'), '');
      if (normalized.isEmpty) continue;
      if (segments.isEmpty || segments.last != normalized) {
        segments.add(normalized);
      }
    }
    return segments.isEmpty ? '' : '/${segments.join('/')}';
  }
}
