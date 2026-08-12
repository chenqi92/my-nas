import 'dart:io';

import 'package:flutter/foundation.dart';

/// Makes Dart HTTP clients honor proxy environment variables on every platform.
///
/// The Windows runner copies the current user's static system proxy into those
/// variables before the Dart VM starts. Literal private addresses and common
/// LAN hostnames stay direct so enabling a desktop proxy cannot break NAS access.
class AppHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = _findProxy;

  String _findProxy(Uri url) {
    if (shouldBypassProxy(url.host)) return 'DIRECT';
    return super.findProxyFromEnvironment(url, Platform.environment);
  }

  @visibleForTesting
  static bool shouldBypassProxy(String host) {
    final normalized = host.trim().toLowerCase();
    if (normalized.isEmpty) return true;

    final address = InternetAddress.tryParse(normalized);
    if (address != null) {
      if (address.isLoopback) return true;
      final bytes = address.rawAddress;
      if (address.type == InternetAddressType.IPv4) {
        return switch ((bytes[0], bytes[1])) {
          (10, _) ||
          (127, _) ||
          (169, 254) ||
          (172, >= 16 && <= 31) ||
          (192, 168) ||
          (100, >= 64 && <= 127) =>
            true,
          _ => false,
        };
      }

      // IPv6 unique-local (fc00::/7) and link-local (fe80::/10).
      return (bytes[0] & 0xfe) == 0xfc ||
          (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80);
    }

    return normalized == 'localhost' ||
        normalized.endsWith('.local') ||
        normalized.endsWith('.lan') ||
        normalized.endsWith('.home.arpa') ||
        !normalized.contains('.');
  }
}
