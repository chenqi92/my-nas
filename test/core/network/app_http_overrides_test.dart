import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/core/network/app_http_overrides.dart';

void main() {
  group('AppHttpOverrides.shouldBypassProxy', () {
    test('keeps local NAS hostnames and private IPv4 addresses direct', () {
      expect(AppHttpOverrides.shouldBypassProxy('nas.local'), isTrue);
      expect(AppHttpOverrides.shouldBypassProxy('MY-NAS'), isTrue);
      expect(AppHttpOverrides.shouldBypassProxy('10.0.0.8'), isTrue);
      expect(AppHttpOverrides.shouldBypassProxy('172.31.0.8'), isTrue);
      expect(AppHttpOverrides.shouldBypassProxy('192.168.1.8'), isTrue);
      expect(AppHttpOverrides.shouldBypassProxy('100.64.1.8'), isTrue);
    });

    test('keeps loopback and private IPv6 addresses direct', () {
      expect(AppHttpOverrides.shouldBypassProxy('::1'), isTrue);
      expect(AppHttpOverrides.shouldBypassProxy('fc00::1'), isTrue);
      expect(AppHttpOverrides.shouldBypassProxy('fe80::1'), isTrue);
    });

    test('allows public endpoints to use the configured proxy', () {
      expect(AppHttpOverrides.shouldBypassProxy('api.themoviedb.org'), isFalse);
      expect(AppHttpOverrides.shouldBypassProxy('8.8.8.8'), isFalse);
      expect(
        AppHttpOverrides.shouldBypassProxy('2001:4860:4860::8888'),
        isFalse,
      );
    });
  });
}
