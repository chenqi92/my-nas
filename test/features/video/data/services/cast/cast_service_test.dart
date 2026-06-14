import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:my_nas/features/video/data/services/cast/adapters/airplay_adapter.dart';
import 'package:my_nas/features/video/data/services/cast/adapters/dlna_adapter.dart';
import 'package:my_nas/features/video/data/services/cast/cast_media_proxy_server.dart';
import 'package:my_nas/features/video/data/services/cast/cast_service.dart';
import 'package:my_nas/features/video/domain/entities/cast_device.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

class MockCastMediaProxyServer extends Mock implements CastMediaProxyServer {}

class MockDlnaAdapter extends Mock implements DlnaAdapter {}

class MockAirPlayAdapter extends Mock implements AirPlayAdapter {}

class MockNasFileSystem extends Mock implements NasFileSystem {}

class FakeNasFileSystem extends Fake implements NasFileSystem {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeNasFileSystem());
    registerFallbackValue(Duration.zero);
  });
  group('CastService', () {
    late CastService castService;
    late MockCastMediaProxyServer mockProxyServer;
    late MockDlnaAdapter mockDlnaAdapter;
    late MockAirPlayAdapter mockAirPlayAdapter;
    late MockNasFileSystem mockFileSystem;
    late StreamController<List<CastDevice>> dlnaDeviceController;
    late StreamController<List<CastDevice>> airplayDeviceController;

    CastService createCastService() {
      mockProxyServer = MockCastMediaProxyServer();
      mockDlnaAdapter = MockDlnaAdapter();
      mockAirPlayAdapter = MockAirPlayAdapter();
      mockFileSystem = MockNasFileSystem();
      dlnaDeviceController = StreamController<List<CastDevice>>.broadcast();
      airplayDeviceController = StreamController<List<CastDevice>>.broadcast();

      // Setup default mock responses BEFORE creating CastService
      when(
        () => mockDlnaAdapter.deviceStream,
      ).thenAnswer((_) => dlnaDeviceController.stream);
      when(
        () => mockAirPlayAdapter.deviceStream,
      ).thenAnswer((_) => airplayDeviceController.stream);
      when(() => mockDlnaAdapter.dispose()).thenReturn(null);
      when(() => mockAirPlayAdapter.dispose()).thenAnswer((_) async {});
      when(() => mockProxyServer.stop()).thenAnswer((_) async {});

      return CastService(
        proxyServer: mockProxyServer,
        dlnaAdapter: mockDlnaAdapter,
        airplayAdapter: mockAirPlayAdapter,
      );
    }

    group('Device discovery', () {
      setUp(() {
        castService = createCastService();
      });

      tearDown(() async {
        await dlnaDeviceController.close();
        await airplayDeviceController.close();
        // Don't call dispose here to avoid mock conflicts
      });

      test('should start discovery on both adapters', () async {
        when(
          () => mockDlnaAdapter.startDiscovery(timeout: any(named: 'timeout')),
        ).thenAnswer((_) async {});
        when(
          () =>
              mockAirPlayAdapter.startDiscovery(timeout: any(named: 'timeout')),
        ).thenAnswer((_) async {});

        await castService.startDiscovery();

        verify(
          () => mockDlnaAdapter.startDiscovery(timeout: any(named: 'timeout')),
        ).called(1);
        verify(
          () =>
              mockAirPlayAdapter.startDiscovery(timeout: any(named: 'timeout')),
        ).called(1);
      });

      test('should stop discovery on both adapters', () {
        when(() => mockDlnaAdapter.stopDiscovery()).thenReturn(null);
        when(() => mockAirPlayAdapter.stopDiscovery()).thenAnswer((_) async {});

        castService.stopDiscovery();

        verify(() => mockDlnaAdapter.stopDiscovery()).called(1);
        verify(() => mockAirPlayAdapter.stopDiscovery()).called(1);
      });

      test('should combine devices from both adapters', () {
        when(() => mockDlnaAdapter.getDiscoveredDevices()).thenReturn([
          const CastDevice(
            id: 'dlna-1',
            name: 'DLNA Device',
            protocol: CastProtocol.dlna,
            address: '192.168.1.100',
            port: 1234,
          ),
        ]);
        when(() => mockAirPlayAdapter.getDiscoveredDevices()).thenReturn([
          const CastDevice(
            id: 'airplay-1',
            name: 'AirPlay Device',
            protocol: CastProtocol.airplay,
            address: '192.168.1.101',
            port: 7000,
          ),
        ]);

        final devices = castService.getDiscoveredDevices();

        expect(devices.length, equals(2));
        expect(devices.any((d) => d.protocol == CastProtocol.dlna), isTrue);
        expect(devices.any((d) => d.protocol == CastProtocol.airplay), isTrue);
      });
    });

    group('Casting', () {
      const testDevice = CastDevice(
        id: 'test-device',
        name: 'Test Device',
        protocol: CastProtocol.dlna,
        address: '192.168.1.100',
        port: 1234,
      );

      setUp(() {
        castService = createCastService();
      });

      tearDown(() async {
        await dlnaDeviceController.close();
        await airplayDeviceController.close();
      });

      test('should cast video successfully', () async {
        when(() => mockProxyServer.ensureRunning()).thenAnswer((_) async {});
        when(
          () => mockProxyServer.registerStream(
            path: any(named: 'path'),
            fileSystem: any(named: 'fileSystem'),
            fileSize: any(named: 'fileSize'),
            subtitlePath: any(named: 'subtitlePath'),
          ),
        ).thenReturn('test-token');
        when(
          () => mockProxyServer.getStreamUrl(any()),
        ).thenAnswer((_) async => 'http://192.168.1.1:8899/stream/test-token');
        when(
          () => mockProxyServer.getSubtitleUrl(any()),
        ).thenAnswer((_) async => null);
        when(
          () => mockDlnaAdapter.castVideo(
            deviceId: any(named: 'deviceId'),
            videoUrl: any(named: 'videoUrl'),
            title: any(named: 'title'),
            subtitleUrl: any(named: 'subtitleUrl'),
          ),
        ).thenAnswer((_) async => true);

        final session = await castService.cast(
          device: testDevice,
          videoPath: '/test/video.mp4',
          videoTitle: 'Test Video',
          fileSystem: mockFileSystem,
        );

        expect(session, isNotNull);
        expect(session!.device, equals(testDevice));
        expect(session.videoTitle, equals('Test Video'));
        expect(castService.isCasting, isTrue);
      });

      test('should handle cast failure', () async {
        when(() => mockProxyServer.ensureRunning()).thenAnswer((_) async {});
        when(
          () => mockProxyServer.registerStream(
            path: any(named: 'path'),
            fileSystem: any(named: 'fileSystem'),
            fileSize: any(named: 'fileSize'),
            subtitlePath: any(named: 'subtitlePath'),
          ),
        ).thenReturn('test-token');
        when(
          () => mockProxyServer.getStreamUrl(any()),
        ).thenAnswer((_) async => 'http://192.168.1.1:8899/stream/test-token');
        when(
          () => mockProxyServer.getSubtitleUrl(any()),
        ).thenAnswer((_) async => null);
        when(() => mockProxyServer.unregisterStream(any())).thenReturn(null);
        when(
          () => mockDlnaAdapter.castVideo(
            deviceId: any(named: 'deviceId'),
            videoUrl: any(named: 'videoUrl'),
            title: any(named: 'title'),
            subtitleUrl: any(named: 'subtitleUrl'),
          ),
        ).thenAnswer((_) async => false);

        final session = await castService.cast(
          device: testDevice,
          videoPath: '/test/video.mp4',
          videoTitle: 'Test Video',
          fileSystem: mockFileSystem,
        );

        expect(session, isNull);
        expect(castService.isCasting, isFalse);
        verify(() => mockProxyServer.unregisterStream('test-token')).called(1);
      });

      test('should handle IP address failure', () async {
        when(() => mockProxyServer.ensureRunning()).thenAnswer((_) async {});
        when(
          () => mockProxyServer.registerStream(
            path: any(named: 'path'),
            fileSystem: any(named: 'fileSystem'),
            fileSize: any(named: 'fileSize'),
            subtitlePath: any(named: 'subtitlePath'),
          ),
        ).thenReturn('test-token');
        when(
          () => mockProxyServer.getStreamUrl(any()),
        ).thenAnswer((_) async => null);
        when(() => mockProxyServer.unregisterStream(any())).thenReturn(null);

        final session = await castService.cast(
          device: testDevice,
          videoPath: '/test/video.mp4',
          videoTitle: 'Test Video',
          fileSystem: mockFileSystem,
        );

        expect(session, isNull);
      });
    });

    group('Playback controls', () {
      setUp(() {
        castService = createCastService();
      });

      tearDown(() async {
        await dlnaDeviceController.close();
        await airplayDeviceController.close();
      });

      test('should not throw when no session', () async {
        await castService.play();
        await castService.pause();
        await castService.seek(const Duration(seconds: 30));
        await castService.setVolume(0.5);
        await castService.stop();
        // Should not throw
      });
    });

    group('Session management', () {
      setUp(() {
        castService = createCastService();
      });

      tearDown(() async {
        await dlnaDeviceController.close();
        await airplayDeviceController.close();
      });

      test('should emit session changes through stream', () async {
        final sessions = <CastSession?>[];
        final subscription = castService.sessionStream.listen(sessions.add);

        // Setup for successful cast
        when(() => mockProxyServer.ensureRunning()).thenAnswer((_) async {});
        when(
          () => mockProxyServer.registerStream(
            path: any(named: 'path'),
            fileSystem: any(named: 'fileSystem'),
            fileSize: any(named: 'fileSize'),
            subtitlePath: any(named: 'subtitlePath'),
          ),
        ).thenReturn('test-token');
        when(
          () => mockProxyServer.getStreamUrl(any()),
        ).thenAnswer((_) async => 'http://192.168.1.1:8899/stream/test-token');
        when(
          () => mockProxyServer.getSubtitleUrl(any()),
        ).thenAnswer((_) async => null);
        when(() => mockProxyServer.unregisterStream(any())).thenReturn(null);
        when(
          () => mockDlnaAdapter.castVideo(
            deviceId: any(named: 'deviceId'),
            videoUrl: any(named: 'videoUrl'),
            title: any(named: 'title'),
            subtitleUrl: any(named: 'subtitleUrl'),
          ),
        ).thenAnswer((_) async => true);
        when(() => mockDlnaAdapter.stop()).thenAnswer((_) async {});

        const testDevice = CastDevice(
          id: 'test-device',
          name: 'Test Device',
          protocol: CastProtocol.dlna,
          address: '192.168.1.100',
          port: 1234,
        );

        await castService.cast(
          device: testDevice,
          videoPath: '/test/video.mp4',
          videoTitle: 'Test Video',
          fileSystem: mockFileSystem,
        );

        await castService.stop();

        // Wait for stream events to be processed
        await Future<void>.delayed(const Duration(milliseconds: 100));

        await subscription.cancel();

        // Should have emitted at least the session
        expect(sessions.isNotEmpty, isTrue);
        // After stop, last should be null (session cleared)
        expect(castService.currentSession, isNull);
      });
    });
  });
}
