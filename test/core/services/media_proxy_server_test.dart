import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:my_nas/core/services/media_proxy_server.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

class _MockNasFileSystem extends Mock implements NasFileSystem {}

class _HttpResult {
  const _HttpResult({
    required this.statusCode,
    required this.body,
    required this.headers,
  });

  final int statusCode;
  final List<int> body;
  final HttpHeaders headers;
}

void main() {
  setUpAll(() {
    registerFallbackValue(const FileRange(start: 0, end: 1));
  });

  group('MediaProxyServer', () {
    late _MockNasFileSystem fileSystem;
    late MediaProxyServer server;
    late Uint8List bytes;
    late String url;

    setUp(() async {
      bytes = Uint8List.fromList(List<int>.generate(16, (index) => index));
      fileSystem = _MockNasFileSystem();
      when(() => fileSystem.getFileInfo(any())).thenAnswer(
        (_) async => FileItem(
          name: 'video.mp4',
          path: '/video.mp4',
          isDirectory: false,
          size: bytes.length,
        ),
      );
      when(
        () => fileSystem.getFileStream(any(), range: any(named: 'range')),
      ).thenAnswer((invocation) async {
        final range = invocation.namedArguments[#range] as FileRange?;
        final start = range?.start ?? 0;
        final end = range?.end ?? bytes.length;
        return Stream<List<int>>.value(bytes.sublist(start, end));
      });

      server = MediaProxyServer.forTesting(
        fileSystemResolver: (_) async => fileSystem,
      );
      // 故意传错媒体库大小，代理必须以文件系统真实大小为准。
      url = await server.registerFile(
        sourceId: 'source',
        filePath: '/video.mp4',
        fileSize: 1,
      );
    });

    tearDown(() async {
      await server.stop();
    });

    test('serves an exact range using the actual file size', () async {
      final result = await _request(url, range: 'bytes=3-5');

      expect(result.statusCode, HttpStatus.partialContent);
      expect(result.body, [3, 4, 5]);
      expect(result.headers.contentLength, 3);
      expect(
        result.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 3-5/16',
      );
      expect(result.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
    });

    test('supports open-ended and suffix ranges', () async {
      final openEnded = await _request(url, range: 'bytes=13-');
      final suffix = await _request(url, range: 'bytes=-4');

      expect(openEnded.statusCode, HttpStatus.partialContent);
      expect(openEnded.body, [13, 14, 15]);
      expect(suffix.statusCode, HttpStatus.partialContent);
      expect(suffix.body, [12, 13, 14, 15]);
    });

    test('rejects malformed and unsatisfiable ranges with 416', () async {
      for (final range in <String>[
        'bytes=16-',
        'bytes=8-7',
        'bytes=-0',
        'bytes=0-1,4-5',
        'items=0-1',
      ]) {
        final result = await _request(url, range: range);
        expect(result.statusCode, HttpStatus.requestedRangeNotSatisfiable);
        expect(
          result.headers.value(HttpHeaders.contentRangeHeader),
          'bytes */16',
        );
      }
    });

    test('HEAD reports metadata without opening a backend stream', () async {
      final result = await _request(url, method: 'HEAD');

      expect(result.statusCode, HttpStatus.ok);
      expect(result.headers.contentLength, bytes.length);
      expect(result.body, isEmpty);
      verifyNever(
        () => fileSystem.getFileStream(any(), range: any(named: 'range')),
      );
    });

    test('unregistering media cancels its active backend stream', () async {
      final streamRequested = Completer<void>();
      final streamCancelled = Completer<void>();
      final controller = StreamController<List<int>>(
        onCancel: () {
          if (!streamCancelled.isCompleted) streamCancelled.complete();
        },
      );
      when(
        () => fileSystem.getFileStream(any(), range: any(named: 'range')),
      ).thenAnswer((_) async {
        if (!streamRequested.isCompleted) streamRequested.complete();
        return controller.stream;
      });

      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      request
        ..persistentConnection = false
        ..headers.set(HttpHeaders.rangeHeader, 'bytes=0-');
      final responseFuture = request.close();
      unawaited(
        responseFuture.then<void>(
          (_) {},
          onError: (_) {},
        ),
      );

      await streamRequested.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);

      server.unregisterFile(Uri.parse(url).pathSegments.last);
      client.close(force: true);
      await streamCancelled.future.timeout(const Duration(seconds: 2));
      await controller.close();
    });
  });
}

Future<_HttpResult> _request(
  String url, {
  String method = 'GET',
  String? range,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, Uri.parse(url));
    if (range != null) {
      request.headers.set(HttpHeaders.rangeHeader, range);
    }
    final response = await request.close();
    final body = await response.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    return _HttpResult(
      statusCode: response.statusCode,
      body: body,
      headers: response.headers,
    );
  } finally {
    client.close(force: true);
  }
}
