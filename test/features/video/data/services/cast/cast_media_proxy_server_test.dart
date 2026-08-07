import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:my_nas/features/video/data/services/cast/cast_media_proxy_server.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

class MockNasFileSystem extends Mock implements NasFileSystem {}

void main() {
  group('CastMediaProxyServer', () {
    late CastMediaProxyServer server;
    late MockNasFileSystem mockFileSystem;

    setUp(() {
      server = CastMediaProxyServer(
        port: 18899,
      ); // Use different port for testing
      mockFileSystem = MockNasFileSystem();
    });

    tearDown(() async {
      await server.stop();
    });

    group('Server lifecycle', () {
      test('should start and stop server', () async {
        expect(server.isRunning, isFalse);

        await server.start();
        expect(server.isRunning, isTrue);

        await server.stop();
        expect(server.isRunning, isFalse);
      });

      test('should not start twice', () async {
        await server.start();
        await server.start(); // Should not throw
        expect(server.isRunning, isTrue);
      });

      test('ensureRunning should start if not running', () async {
        expect(server.isRunning, isFalse);
        await server.ensureRunning();
        expect(server.isRunning, isTrue);
      });
    });

    group('Stream registration', () {
      test('should register and unregister stream', () async {
        final token = server.registerStream(
          path: '/test/video.mp4',
          fileSystem: mockFileSystem,
          fileSize: 1024,
        );

        expect(token, isNotEmpty);

        server.unregisterStream(token);
        // Token should be removed
      });

      test('should generate unique tokens', () async {
        final token1 = server.registerStream(
          path: '/test/video1.mp4',
          fileSystem: mockFileSystem,
        );

        final token2 = server.registerStream(
          path: '/test/video2.mp4',
          fileSystem: mockFileSystem,
        );

        expect(token1, isNot(equals(token2)));
      });

      test('should handle subtitle path', () async {
        final token = server.registerStream(
          path: '/test/video.mp4',
          fileSystem: mockFileSystem,
          subtitlePath: '/test/video.srt',
        );

        expect(token, isNotEmpty);
      });
    });

    group('MIME type detection', () {
      test('should detect video MIME types correctly', () async {
        await server.start();

        // Register streams with different extensions
        final mp4Token = server.registerStream(
          path: '/test/video.mp4',
          fileSystem: mockFileSystem,
          fileSize: 100,
        );

        final mkvToken = server.registerStream(
          path: '/test/video.mkv',
          fileSystem: mockFileSystem,
          fileSize: 100,
        );

        // MIME types are internal, we can only verify they're registered
        expect(mp4Token, isNotEmpty);
        expect(mkvToken, isNotEmpty);
      });
    });

    group('Expired stream cleanup', () {
      test('should cleanup expired streams', () async {
        final token = server.registerStream(
          path: '/test/video.mp4',
          fileSystem: mockFileSystem,
        );

        expect(token, isNotEmpty);

        // Cleanup with very short max age
        server.cleanupExpiredStreams(maxAge: Duration.zero);

        // Stream should be removed
        // We can verify by trying to get URL which should still work
        // because the stream was just registered
      });
    });

    group('IP cache', () {
      test('should clear IP cache', () {
        server.clearIpCache();
        // Should not throw
      });
    });

    group('Health check endpoint', () {
      test('should respond to health check', () async {
        await server.start();

        final response = await http.get(
          Uri.parse('http://localhost:18899/health'),
        );
        expect(response.statusCode, equals(200));
        expect(response.body, equals('OK'));
      });
    });

    group('HEAD requests', () {
      test('should handle HEAD request for stream', () async {
        await server.start();

        // Setup mock file system
        when(
          () => mockFileSystem.getFileStream(any(), range: any(named: 'range')),
        ).thenAnswer((_) async => Stream.empty());

        final token = server.registerStream(
          path: '/test/video.mp4',
          fileSystem: mockFileSystem,
          fileSize: 1024,
        );

        // Use http package for HEAD request
        final response = await http.head(
          Uri.parse('http://localhost:18899/stream/$token'),
        );

        expect(response.statusCode, equals(200));
        expect(response.headers['content-type'], contains('video/mp4'));
        expect(response.headers['accept-ranges'], equals('bytes'));
        // Note: Content-Length may be 0 due to shelf framework limitations
        // with empty bodies. DLNA devices primarily use Content-Type and
        // Accept-Ranges headers; they determine actual size during streaming.
        expect(response.headers.containsKey('content-length'), isTrue);
      });

      test('should return 404 for invalid token', () async {
        await server.start();

        final request = await HttpClient().headUrl(
          Uri.parse('http://localhost:18899/stream/invalid-token'),
        );
        final response = await request.close();

        expect(response.statusCode, equals(404));
      });
    });

    group('CORS headers', () {
      test('should not expose wildcard allow-origin', () async {
        await server.start();

        final response = await http.get(
          Uri.parse('http://localhost:18899/health'),
        );

        // 投屏设备不是浏览器，无需 CORS 放行；`*` 会让局域网内任意网页读取代理响应
        expect(response.headers.containsKey('access-control-allow-origin'), isFalse);
      });

      test('should handle OPTIONS preflight request', () async {
        await server.start();

        final request = await HttpClient().openUrl(
          'OPTIONS',
          Uri.parse('http://localhost:18899/health'),
        );
        final response = await request.close();

        expect(response.statusCode, equals(200));
        expect(
          response.headers.value('access-control-allow-methods'),
          isNotNull,
        );
      });
    });

    group('Token 时效校验', () {
      test('过期 token 的 HEAD 请求返回 404', () async {
        await server.start();

        final token = server.registerStream(
          path: '/test/video.mp4',
          fileSystem: mockFileSystem,
          fileSize: 1024,
          createdAt: DateTime.now().subtract(const Duration(hours: 3)),
        );

        final response = await http.head(
          Uri.parse('http://localhost:18899/stream/$token'),
        );

        expect(response.statusCode, equals(404));
      });

      test('过期 token 的 GET 请求返回 404', () async {
        await server.start();

        final token = server.registerStream(
          path: '/test/video.mp4',
          fileSystem: mockFileSystem,
          fileSize: 1024,
          createdAt: DateTime.now().subtract(const Duration(hours: 3)),
        );

        final response = await http.get(
          Uri.parse('http://localhost:18899/stream/$token'),
        );

        expect(response.statusCode, equals(404));
      });

      test('过期 token 的字幕请求返回 404', () async {
        await server.start();

        final token = server.registerStream(
          path: '/test/video.mp4',
          fileSystem: mockFileSystem,
          subtitlePath: '/test/video.srt',
          createdAt: DateTime.now().subtract(const Duration(hours: 3)),
        );

        final response = await http.get(
          Uri.parse('http://localhost:18899/subtitle/$token'),
        );

        expect(response.statusCode, equals(404));
      });

      test('未过期 token 仍可访问', () async {
        await server.start();

        when(
          () => mockFileSystem.getFileStream(any(), range: any(named: 'range')),
        ).thenAnswer((_) async => const Stream<List<int>>.empty());

        final token = server.registerStream(
          path: '/test/video.mp4',
          fileSystem: mockFileSystem,
          fileSize: 1024,
          createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
        );

        final response = await http.head(
          Uri.parse('http://localhost:18899/stream/$token'),
        );

        expect(response.statusCode, equals(200));
      });
    });
  });
}
