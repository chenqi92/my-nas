import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/pt_sites/data/services/pt_site_api.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';

void main() {
  group('PTSiteApi transfer statistics capability', () {
    test('generic trackers do not advertise transfer statistics', () {
      final api = PTSiteApiFactory.create(_source(host: 'tracker.example.com'));
      addTearDown(api.dispose);

      expect(api, isA<GenericPTSiteApi>());
      expect(api.supportsTransferStats, isFalse);
    });

    test('M-Team advertises its implemented transfer statistics API', () {
      final api = PTSiteApiFactory.create(_source(host: 'api.m-team.cc'));
      addTearDown(api.dispose);

      expect(api, isA<MTeamApi>());
      expect(api.supportsTransferStats, isTrue);
    });
  });

  group('PTSiteApi check-in', () {
    test('only advertises check-in when an endpoint is configured', () {
      final plain = PTSiteApiFactory.create(
        _source(host: 'tracker.example.com'),
      );
      final configured = PTSiteApiFactory.create(
        _source(
          host: 'tracker.example.com',
          extraConfig: const {'checkInPath': '/attendance.php'},
        ),
      );
      addTearDown(plain.dispose);
      addTearDown(configured.dispose);

      expect(plain.supportsCheckIn, isFalse);
      expect(configured.supportsCheckIn, isTrue);
    });

    test('calls the configured endpoint with tracker authentication', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requestFuture = server.first.then((request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/attendance.php');
        expect(request.headers.value(HttpHeaders.cookieHeader), 'session=test');
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'success': true, 'message': '获得 10 魔力'}));
        await request.response.close();
      });
      final api = PTSiteApiFactory.create(
        _source(
          host: InternetAddress.loopbackIPv4.address,
          port: server.port,
          extraConfig: const {
            'cookie': 'session=test',
            'checkInPath': '/attendance.php',
            'checkInMethod': 'POST',
          },
        ),
      );
      addTearDown(api.dispose);

      final result = await api.checkIn();
      await requestFuture;

      expect(result.success, isTrue);
      expect(result.message, '获得 10 魔力');
    });

    test('recognizes already checked in and failure responses', () {
      final already = parsePTCheckInResponse(200, '{"message":"今日已签到"}');
      final failed = parsePTCheckInResponse(403, 'check-in failed');
      final successCode = parsePTCheckInResponse(
        200,
        '{"code":"SUCCESS","message":"checked in"}',
      );

      expect(already.success, isTrue);
      expect(already.alreadyCheckedIn, isTrue);
      expect(failed.success, isFalse);
      expect(successCode.success, isTrue);
    });

    test('rejects cross-origin endpoint before sending credentials', () async {
      final api = PTSiteApiFactory.create(
        _source(
          host: 'tracker.example.com',
          extraConfig: const {
            'cookie': 'session=secret',
            'checkInPath': 'https://attacker.example/collect',
          },
        ),
      );
      addTearDown(api.dispose);

      await expectLater(api.checkIn(), throwsA(isA<StateError>()));
    });
  });
}

SourceEntity _source({
  required String host,
  int? port,
  Map<String, dynamic>? extraConfig,
}) => SourceEntity(
  name: 'Test tracker',
  type: SourceType.ptSite,
  host: host,
  port: port ?? 443,
  useSsl: port == null,
  username: 'tester',
  extraConfig: extraConfig,
);
