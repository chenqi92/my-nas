import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:my_nas/core/network/dio_client.dart';
import 'package:my_nas/core/network/tls_trust_store.dart';

void main() {
  test(
    'shared Dio prompts, saves the endpoint certificate, and retries once',
    () async {
      final hiveDirectory = await Directory.systemTemp.createTemp(
        'mynas_tls_aware_dio_test_',
      );
      Hive.init(hiveDirectory.path);

      final securityContext = SecurityContext()
        ..useCertificateChainBytes(utf8.encode(_testCertificate))
        ..usePrivateKeyBytes(utf8.encode(_testPrivateKey));
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        securityContext,
      );
      final serverSubscription = server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..write('trusted');
        await request.response.close();
      });
      final dio = DioClient.createTlsAware();

      addTearDown(() async {
        dio.close(force: true);
        await serverSubscription.cancel();
        await server.close(force: true);
        await Hive.close();
        if (await hiveDirectory.exists()) {
          await hiveDirectory.delete(recursive: true);
        }
      });

      await TlsTrustStore.load();
      final firstResponseFuture = dio.get<String>(
        'https://127.0.0.1:${server.port}/scraper',
      );
      final trustRequest = await _nextTrustRequest();

      expect(trustRequest.certificate.host, '127.0.0.1');
      expect(trustRequest.certificate.port, server.port);
      expect(trustRequest.certificateChanged, isFalse);

      await TlsTrustStore.resolveTrustRequest(trustRequest, approved: true);
      final firstResponse = await firstResponseFuture.timeout(
        const Duration(seconds: 10),
      );
      expect(firstResponse.data, 'trusted');
      expect(TlsTrustStore.pendingRequest.value, isNull);

      final secondResponse = await dio
          .get<String>('https://127.0.0.1:${server.port}/scraper-again')
          .timeout(const Duration(seconds: 10));
      expect(secondResponse.data, 'trusted');
      expect(TlsTrustStore.pendingRequest.value, isNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

const _testCertificate = '''
-----BEGIN CERTIFICATE-----
MIIDGjCCAgKgAwIBAgIUXRzNopZ3ytr3sbRa7tUn1skbw9wwDQYJKoZIhvcNAQEL
BQAwFDESMBAGA1UEAwwJMTI3LjAuMC4xMB4XDTI2MDcyNjExNTgxM1oXDTM2MDcy
MzExNTgxM1owFDESMBAGA1UEAwwJMTI3LjAuMC4xMIIBIjANBgkqhkiG9w0BAQEF
AAOCAQ8AMIIBCgKCAQEApZ8dCGgULJh61xma05dIBvc50+nlk6oYGgbwWXPGBJIV
shjHCc54INA14lily/K6BzLEdxCtRAWK4NLxbhqIc1fixImfqijj2c2Aqu5BeYEv
ODT0vwUwOK22N5KgftcHkraRPGQQJdl+ttb3T0Y0OBHAWpP09TeOjZKQKwyaCF65
ak6c4r7nvms38E6lQU1mcaUgU86l56K53l6QIjtwvfRXcA7/Bd6uatMYdglqBOj6
Jjjw53sx73KWOfoQ2SGYWCs3jQneDBRsLfxwKh8zI6mSPMICeq5jF8qUap6FXVic
j1tx32/W9wXwLq74OeLPKpBIYBKkm3Bs3G0aep+oIwIDAQABo2QwYjAdBgNVHQ4E
FgQU0LMbV1I5Wlgi1lUYjQIR0o/8+OwwHwYDVR0jBBgwFoAU0LMbV1I5Wlgi1lUY
jQIR0o/8+OwwDwYDVR0TAQH/BAUwAwEB/zAPBgNVHREECDAGhwR/AAABMA0GCSqG
SIb3DQEBCwUAA4IBAQBstA+a5wDPksCJkTPZGggaX559RGI4Y4Zv6siqp8lHLC9O
ihJcnR1NYPF+IGvWWwjuQ7Rab3F83R6KZtHu/wKBknIFy7Cu8ZvBuB6kJ3g+ct77
hDUR+9ffVGooQMx0WHVKgTaDDO4FUEMbOAwUVimM7zicSca7DvM0DKX993sCc+nW
KxeKNlWjODJTSwVUdCOVw3ynBCCt8LUW0yYGEYVxxPbMBVvkFdkwHCH1Wwoy/mG8
RkFqqtoMdrt8CUeUiQ+z6hG2Yw7/2U92DU2Qv1Y1GFtVdhsWm5+x8rP48NuLZ37s
sR8jU+a77QHTr/wwnt2124L4Tg5A27ji4g84cevT
-----END CERTIFICATE-----
''';

const _testPrivateKey = '''
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQClnx0IaBQsmHrX
GZrTl0gG9znT6eWTqhgaBvBZc8YEkhWyGMcJzngg0DXiWKXL8roHMsR3EK1EBYrg
0vFuGohzV+LEiZ+qKOPZzYCq7kF5gS84NPS/BTA4rbY3kqB+1weStpE8ZBAl2X62
1vdPRjQ4EcBak/T1N46NkpArDJoIXrlqTpzivue+azfwTqVBTWZxpSBTzqXnorne
XpAiO3C99FdwDv8F3q5q0xh2CWoE6PomOPDnezHvcpY5+hDZIZhYKzeNCd4MFGwt
/HAqHzMjqZI8wgJ6rmMXypRqnoVdWJyPW3Hfb9b3BfAurvg54s8qkEhgEqSbcGzc
bRp6n6gjAgMBAAECggEADqUSKSMi3YqiGhEOirUuzkbgGyfsf/EjbnG8oPxGvzK3
rmbYerqCDsy6ZwhVqMIOxwIrMygLWh9vV0/vvz+jXyefSqessZwqAaFVRkgJDBhr
N3ofRiDMUcayfRl/DZgv+D4ie4eRkfc4aCx788uOZILVUm0Q1PoTpdsW2mej2yd4
l9jUt8Gpvndq3L3fiFkHwTyeYKKt4LoTEBPcHyttMV08h6FGlbMLB2i9RLANlqlT
BTY4zHQobEdqt5WTgxykxvnrTke6irSbDkGx06I2BDNEAzRXqvP/d7KJEJnNlJ5/
1JvTxzwgjy8WDh1HjZmWe0mcs/mHWFXC+98MxN3GoQKBgQDcacioDLrsztGWwfH1
ELclhqfCnTb4WNVWl6aa570Mk1nRPH33OGfJdEUQ9ConnWuxydpMTd2AZPdsOqMv
9Z4+ljuz21SEHanatlV8pZrtwiVnn4pRsLMEU5IYbfhVh9+JDRAcqckwTlSHGH23
a1TZyzf5yoETrNe2PZhHGTh+8QKBgQDAXKfbznHS6CCSo+HHSLnxeke7OP9hbLNV
T1YZaEevc5uLgioL9MwqhTWaavmIK7kcbRoJgy0uwrlogaVJYPdRSuUIQfEKe9Ez
HQ7kyuMtMs9M6wo9NiO6fUYZ3bAHtBKGGMXcKiAOSDpvFfTsZE4TjNeUF2RFh5LH
malItzaAUwKBgDPYzlJ5bB74J2UHChtTa0Fwg1XMFXolq0lLMu2NRXMH1kDZsefN
ZNyGdRif1qqq5QJVMPxx9ICXP3w97tUBOdAPFswf86mAMMw5x7IiYmc7HAFcDfVZ
U0LZRaxpcdjstTBP2lJjveeXBVsh77CNltAEdY5UjDhMmBFOO9u9mwSBAoGBAJQT
fz/MNoClIdXgA8BVcpW5jJhJswU7GP11uhCK3ovoEXed9mIHylZ8/ptk97tj9PY1
4hIqgVB6oyEYk7TdyOQyJAZsRHHOiGaxWrKyn5g+gadzUwl1sKExKBJnPcdgTdYe
IcluQAjefuTeYRDL0fJou9aK/ywqxcmStuZ76p9zAoGBAJM5azgqqOxDtFkhPatL
Wrb8iHrbA5DcebNFTImBdUJHbg+unJ8el20fDmCA5CwCsqiesklhNRwWzhIqQD7L
VI+sR14P2/Pq8AQH1K0QF7XYLk4jr67X84wMCorJnDLJ2TlPuOfg+vDX2YK6k8N9
WZYpl/01fpxt5hr/ELrJgXxQ
-----END PRIVATE KEY-----
''';

Future<TlsTrustRequest> _nextTrustRequest() async {
  final current = TlsTrustStore.pendingRequest.value;
  if (current != null) return current;

  final completer = Completer<TlsTrustRequest>();
  void listener() {
    final request = TlsTrustStore.pendingRequest.value;
    if (request != null && !completer.isCompleted) {
      completer.complete(request);
    }
  }

  TlsTrustStore.pendingRequest.addListener(listener);
  try {
    return await completer.future.timeout(const Duration(seconds: 10));
  } finally {
    TlsTrustStore.pendingRequest.removeListener(listener);
  }
}
