import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/video/presentation/providers/playback_settings_provider.dart';

void main() {
  test(
    'older settings retain defaults and unknown orientation values are safe',
    () {
      expect(
        PlaybackSettings.fromMap({}).orientation,
        PlaybackOrientation.auto,
      );
      expect(
        PlaybackSettings.fromMap({'orientation': 'future'}).orientation,
        PlaybackOrientation.auto,
      );
      expect(PlaybackSettings.fromMap({}).hideSystemBars, isFalse);
    },
  );
  test(
    'all orientation choices and system bar preference survive persistence',
    () {
      for (final orientation in PlaybackOrientation.values) {
        final settings = PlaybackSettings(
          orientation: orientation,
          hideSystemBars: true,
        );
        final restored = PlaybackSettings.fromMap(settings.toMap());
        expect(restored.orientation, orientation);
        expect(restored.hideSystemBars, isTrue);
      }
    },
  );
  test(
    'video mode respects portrait video and waits for unknown dimensions',
    () {
      expect(PlaybackOrientation.video.orientations(), isEmpty);
      expect(PlaybackOrientation.video.orientations(aspectRatio: 9 / 16), [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      expect(PlaybackOrientation.video.orientations(aspectRatio: 16 / 9), [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      expect(PlaybackOrientation.reversePortrait.orientations(), [
        DeviceOrientation.portraitDown,
      ]);
      expect(PlaybackOrientation.reverseLandscape.orientations(), [
        DeviceOrientation.landscapeRight,
      ]);
    },
  );
}
