import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/video/domain/entities/cast_device.dart';

void main() {
  group('CastDevice', () {
    test('should create CastDevice with all fields', () {
      const device = CastDevice(
        id: 'test-id',
        name: 'Test Device',
        protocol: CastProtocol.dlna,
        address: '192.168.1.100',
        port: 1234,
        modelName: 'Model X',
        manufacturer: 'Test Corp',
        iconUrl: 'http://example.com/icon.png',
      );

      expect(device.id, equals('test-id'));
      expect(device.name, equals('Test Device'));
      expect(device.protocol, equals(CastProtocol.dlna));
      expect(device.address, equals('192.168.1.100'));
      expect(device.port, equals(1234));
      expect(device.modelName, equals('Model X'));
      expect(device.manufacturer, equals('Test Corp'));
      expect(device.iconUrl, equals('http://example.com/icon.png'));
    });

    test('fullAddress should return address:port', () {
      const device = CastDevice(
        id: 'test-id',
        name: 'Test Device',
        protocol: CastProtocol.dlna,
        address: '192.168.1.100',
        port: 1234,
      );

      expect(device.fullAddress, equals('192.168.1.100:1234'));
    });

    test('description should return manufacturer and model', () {
      const device = CastDevice(
        id: 'test-id',
        name: 'Test Device',
        protocol: CastProtocol.dlna,
        address: '192.168.1.100',
        port: 1234,
        modelName: 'Model X',
        manufacturer: 'Test Corp',
      );

      expect(device.description, equals('Test Corp · Model X'));
    });

    test(
      'description should return protocol label when no manufacturer/model',
      () {
        const device = CastDevice(
          id: 'test-id',
          name: 'Test Device',
          protocol: CastProtocol.dlna,
          address: '192.168.1.100',
          port: 1234,
        );

        expect(device.description, equals('DLNA'));
      },
    );

    test('equality should be based on id', () {
      const device1 = CastDevice(
        id: 'test-id',
        name: 'Test Device 1',
        protocol: CastProtocol.dlna,
        address: '192.168.1.100',
        port: 1234,
      );

      const device2 = CastDevice(
        id: 'test-id',
        name: 'Test Device 2', // Different name
        protocol: CastProtocol.airplay, // Different protocol
        address: '192.168.1.101', // Different address
        port: 5678, // Different port
      );

      expect(device1, equals(device2));
      expect(device1.hashCode, equals(device2.hashCode));
    });

    test('copyWith should create new instance with updated fields', () {
      const device = CastDevice(
        id: 'test-id',
        name: 'Test Device',
        protocol: CastProtocol.dlna,
        address: '192.168.1.100',
        port: 1234,
      );

      final updatedDevice = device.copyWith(name: 'Updated Name');

      expect(updatedDevice.id, equals('test-id'));
      expect(updatedDevice.name, equals('Updated Name'));
      expect(updatedDevice.protocol, equals(CastProtocol.dlna));
    });
  });

  group('CastSession', () {
    const testDevice = CastDevice(
      id: 'test-id',
      name: 'Test Device',
      protocol: CastProtocol.dlna,
      address: '192.168.1.100',
      port: 1234,
    );

    test('should create CastSession with default values', () {
      final session = CastSession(
        device: testDevice,
        videoTitle: 'Test Video',
        videoPath: '/test/video.mp4',
      );

      expect(session.device, equals(testDevice));
      expect(session.videoTitle, equals('Test Video'));
      expect(session.playbackState, equals(CastPlaybackState.idle));
      expect(session.position, equals(Duration.zero));
      expect(session.duration, equals(Duration.zero));
      expect(session.volume, equals(1.0));
    });

    test('progress should calculate correctly', () {
      final session = CastSession(
        device: testDevice,
        videoTitle: 'Test Video',
        videoPath: '/test/video.mp4',
        position: const Duration(minutes: 5),
        duration: const Duration(minutes: 10),
      );

      expect(session.progress, equals(0.5));
    });

    test('progress should be 0 when duration is 0', () {
      final session = CastSession(
        device: testDevice,
        videoTitle: 'Test Video',
        videoPath: '/test/video.mp4',
        position: const Duration(minutes: 5),
        duration: Duration.zero,
      );

      expect(session.progress, equals(0.0));
    });

    test('isPlaying should be true when playbackState is playing', () {
      final session = CastSession(
        device: testDevice,
        videoTitle: 'Test Video',
        videoPath: '/test/video.mp4',
        playbackState: CastPlaybackState.playing,
      );

      expect(session.isPlaying, isTrue);
      expect(session.isPaused, isFalse);
    });

    test('isPaused should be true when playbackState is paused', () {
      final session = CastSession(
        device: testDevice,
        videoTitle: 'Test Video',
        videoPath: '/test/video.mp4',
        playbackState: CastPlaybackState.paused,
      );

      expect(session.isPaused, isTrue);
      expect(session.isPlaying, isFalse);
    });

    test('hasError should be true when playbackState is error', () {
      final session = CastSession(
        device: testDevice,
        videoTitle: 'Test Video',
        videoPath: '/test/video.mp4',
        playbackState: CastPlaybackState.error,
      );

      expect(session.hasError, isTrue);
    });

    test('isLoading should be true when playbackState is loading', () {
      final session = CastSession(
        device: testDevice,
        videoTitle: 'Test Video',
        videoPath: '/test/video.mp4',
        playbackState: CastPlaybackState.loading,
      );

      expect(session.isLoading, isTrue);
    });

    test('copyWith should create new instance with updated fields', () {
      final session = CastSession(
        device: testDevice,
        videoTitle: 'Test Video',
        videoPath: '/test/video.mp4',
      );

      final updatedSession = session.copyWith(
        playbackState: CastPlaybackState.playing,
        position: const Duration(minutes: 5),
      );

      expect(updatedSession.playbackState, equals(CastPlaybackState.playing));
      expect(updatedSession.position, equals(const Duration(minutes: 5)));
      expect(updatedSession.videoTitle, equals('Test Video'));
    });
  });

  group('CastProtocol', () {
    test('dlna label should be DLNA', () {
      expect(CastProtocol.dlna.label, equals('DLNA'));
    });

    test('airplay label should be AirPlay', () {
      expect(CastProtocol.airplay.label, equals('AirPlay'));
    });
  });

  group('CastPlaybackState', () {
    test('should have all expected states', () {
      expect(CastPlaybackState.values, contains(CastPlaybackState.idle));
      expect(CastPlaybackState.values, contains(CastPlaybackState.loading));
      expect(CastPlaybackState.values, contains(CastPlaybackState.playing));
      expect(CastPlaybackState.values, contains(CastPlaybackState.paused));
      expect(CastPlaybackState.values, contains(CastPlaybackState.stopped));
      expect(CastPlaybackState.values, contains(CastPlaybackState.error));
    });
  });
}
