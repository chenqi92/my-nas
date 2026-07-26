import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/core/network/network_endpoint.dart';
import 'package:my_nas/core/network/tls_trust_store.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/nas_adapters/base/dio_file_stream.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/fnos/api/fnos_api.dart';
import 'package:my_nas/nas_adapters/ugreen/api/ugreen_api.dart';
import 'package:my_nas/nas_adapters/upnp/upnp_content_directory_client.dart';

void main() {
  group('NetworkEndpoint', () {
    test('preserves a full URL path and appends a reverse proxy base path', () {
      expect(
        NetworkEndpoint.buildBaseUrl(
          host: 'https://nas.example.test/proxy',
          port: 80,
          useSsl: false,
          basePath: '/jellyfin',
        ),
        'https://nas.example.test/proxy/jellyfin',
      );
    });

    test('brackets bare IPv6 addresses', () {
      expect(
        NetworkEndpoint.buildBaseUrl(
          host: '2001:db8::10',
          port: 5001,
          useSsl: true,
        ),
        'https://[2001:db8::10]:5001',
      );
    });
  });

  group('TlsTrustStore', () {
    test('scopes trust to a normalized host and port', () {
      expect(
        TlsTrustStore.endpointKey(' NAS.Example.Test ', 5001),
        'nas.example.test:5001',
      );
    });

    test('formats SHA-256 fingerprints for user verification', () {
      expect(TlsTrustStore.formatFingerprint('aabb01'), 'AA:BB:01');
    });

    test(
      'recognizes certificate failures without classifying plain outages',
      () {
        expect(
          TlsTrustStore.isCertificateValidationError(
            HandshakeException('CERTIFICATE_VERIFY_FAILED: Hostname mismatch'),
          ),
          isTrue,
        );
        expect(
          TlsTrustStore.isCertificateValidationError(
            const SocketException('Connection refused'),
          ),
          isFalse,
        );
      },
    );
  });

  test('SourceEntity excludes secrets from persisted JSON', () {
    final source = SourceEntity(
      id: 'source-1',
      name: 'NAS',
      type: SourceType.sftp,
      host: 'nas.local',
      port: 22,
      username: 'alice',
      accessToken: 'access',
      refreshToken: 'refresh',
      apiKey: 'api-key',
      extraConfig: const {
        'path': '/media',
        'password': 'legacy-password',
        'privateKey': 'private-key',
        'privateKeyPassphrase': 'passphrase',
      },
    );

    final json = source.toJson(includeSecrets: false);
    expect(json, isNot(contains('accessToken')));
    expect(json, isNot(contains('refreshToken')));
    expect(json, isNot(contains('apiKey')));
    expect(json['extraConfig'], {'path': '/media'});
  });

  group('SourceEntity password authentication', () {
    SourceEntity source(
      SourceType type, {
      String username = 'alice',
      String? apiKey,
      Map<String, dynamic>? extraConfig,
    }) =>
        SourceEntity(
          name: 'Source',
          type: type,
          host: 'source.local',
          username: username,
          apiKey: apiKey,
          extraConfig: extraConfig,
        );

    test('requires a stored password for password-based services', () {
      expect(source(SourceType.qbittorrent).usesPasswordAuthentication, isTrue);
      expect(source(SourceType.nastool).usesPasswordAuthentication, isTrue);
      expect(source(SourceType.webdav).usesPasswordAuthentication, isTrue);
    });

    test('does not prompt anonymous or token/key-based services', () {
      expect(
        source(SourceType.webdav, username: '').usesPasswordAuthentication,
        isFalse,
      );
      expect(
        source(
          SourceType.jellyfin,
          apiKey: 'api-key',
        ).usesPasswordAuthentication,
        isFalse,
      );
      expect(
        source(
          SourceType.qbittorrent,
          extraConfig: const {'authType': 'API Key'},
        ).usesPasswordAuthentication,
        isFalse,
      );
      expect(
        source(
          SourceType.sftp,
          extraConfig: const {'privateKey': 'pem'},
        ).usesPasswordAuthentication,
        isFalse,
      );
      expect(source(SourceType.upnp).usesPasswordAuthentication, isFalse);
    });
  });

  test('SourceEntity does not reinterpret an unknown source as Synology', () {
    expect(
      () => SourceEntity.fromJson({
        'id': 'legacy-1',
        'name': 'Legacy',
        'type': 'removed_adapter',
        'host': 'nas.local',
      }),
      throwsFormatException,
    );
  });

  group('openDioFileStream', () {
    test('slices locally when a server ignores Range', () async {
      final adapter = _QueueAdapter([
        ResponseBody.fromBytes(
          List<int>.generate(10, (index) => index),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/octet-stream'],
          },
        ),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;

      final stream = await openDioFileStream(
        dio,
        'https://nas.local/file',
        range: const FileRange(start: 3, end: 7),
      );

      expect(await stream.expand((chunk) => chunk).toList(), [3, 4, 5, 6]);
      expect(adapter.requests.single.headers['Range'], 'bytes=3-6');
    });

    test('rejects JSON error bodies returned as HTTP 200', () async {
      final dio = Dio()
        ..httpClientAdapter = _QueueAdapter([
          ResponseBody.fromString(
            '{"code":401,"message":"login required"}',
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          ),
        ]);

      expect(
        () => openDioFileStream(dio, 'https://nas.local/file'),
        throwsStateError,
      );
    });
  });

  test('UPnP Browse paginates and selects the playable resource', () async {
    final adapter = _QueueAdapter([
      ResponseBody.fromString(_soapPage(index: 0, total: 2), 200),
      ResponseBody.fromString(_soapPage(index: 1, total: 2), 200),
    ]);
    final dio = Dio()..httpClientAdapter = adapter;
    final client = UpnpContentDirectoryClient(
      controlUrl: 'http://media.local/control',
      dio: dio,
    );

    final items = await client.browse('0');

    expect(items.map((item) => item.id), ['item-0', 'item-1']);
    expect(items.first.contentUrl, 'http://media.local/video-0.mp4');
    expect(
      adapter.requests[1].data,
      contains('<StartingIndex>1</StartingIndex>'),
    );
  });

  test('fnOS prefers POST listing and safely encodes file paths', () async {
    final adapter = _QueueAdapter([
      ResponseBody.fromString(
        '{"code":200,"data":{"token":"fn-token"}}',
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      ),
      ResponseBody.fromString(
        '{"code":200,"data":{"list":[]}}',
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      ),
    ]);
    final api = FnOSApi(
      dio: Dio(BaseOptions(baseUrl: 'https://fnos.local:5666'))
        ..httpClientAdapter = adapter,
    );

    expect(
      await api.login(username: 'alice', password: 'secret'),
      isA<FnOSAuthSuccess>(),
    );
    expect(await api.listDirectory('/R&B/AC+DC = live?'), isEmpty);

    expect(adapter.requests[1].method, 'POST');
    expect(
      (adapter.requests[1].data as Map<String, dynamic>)['path'],
      '/R&B/AC+DC = live?',
    );
    final download = Uri.parse(await api.getFileUrl('/R&B/AC+DC = live?.flac'));
    expect(download.queryParameters['path'], '/R&B/AC+DC = live?.flac');
    expect(download.queryParameters['token'], 'fn-token');
  });

  test(
    'UGREEN early firmware fallback preserves special path values',
    () async {
      final adapter = _QueueAdapter([
        ResponseBody.fromString('{}', 200),
        ResponseBody.fromString(
          '{"code":200,"data":{"token":"ug-token"}}',
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        ),
        ResponseBody.fromString(
          '{"code":200,"data":{"list":[]}}',
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        ),
      ]);
      final api = UGreenApi(
        dio: Dio(BaseOptions(baseUrl: 'https://ugreen.local:9443'))
          ..httpClientAdapter = adapter,
      );

      expect(
        await api.login(username: 'alice', password: 'secret'),
        isA<UGreenAuthSuccess>(),
      );
      expect(await api.listDirectory('/R&B/AC+DC = live?'), isEmpty);

      expect(adapter.requests[2].path, '/ugreen/v1/filemgr/list');
      expect(
        (adapter.requests[2].data as Map<String, dynamic>)['path'],
        '/R&B/AC+DC = live?',
      );
      final download = Uri.parse(
        await api.getFileUrl('/R&B/AC+DC = live?.flac'),
      );
      expect(download.queryParameters['path'], '/R&B/AC+DC = live?.flac');
      expect(download.queryParameters['token'], 'ug-token');
    },
  );
}

class _QueueAdapter implements HttpClientAdapter {
  _QueueAdapter(this._responses);

  final List<ResponseBody> _responses;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (_responses.isEmpty) throw StateError('No queued response');
    return _responses.removeAt(0);
  }

  @override
  void close({bool force = false}) {}
}

String _soapPage({required int index, required int total}) {
  final didl = '''
<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/"
 xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">
  <item id="item-$index" parentID="0">
    <dc:title>Video $index</dc:title>
    <upnp:class>object.item.videoItem</upnp:class>
    <res protocolInfo="http-get:*:image/jpeg:*">http://media.local/thumb-$index.jpg</res>
    <res protocolInfo="http-get:*:video/mp4:*" size="1000">http://media.local/video-$index.mp4</res>
  </item>
</DIDL-Lite>
''';
  return '''
<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
  <s:Body>
    <u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
      <Result>${const HtmlEscape().convert(didl)}</Result>
      <NumberReturned>1</NumberReturned>
      <TotalMatches>$total</TotalMatches>
    </u:BrowseResponse>
  </s:Body>
</s:Envelope>
''';
}
