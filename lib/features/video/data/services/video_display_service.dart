import 'dart:io';

import 'package:flutter/services.dart';

class VideoDisplayService {
  static const _channel = MethodChannel('my_nas/video_display');
  static int _revision = 0;

  static Future<void> apply({
    required List<DeviceOrientation> orientations,
    required bool hideSystemBars,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final revision = ++_revision;
    await SystemChrome.setPreferredOrientations(orientations);
    if (revision != _revision) return;
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<void>(
          'setSystemBarsHidden',
          hideSystemBars,
        );
        return;
      } on MissingPluginException {
        // Older hosts can still use Flutter's system UI channel.
      }
    }
    await SystemChrome.setEnabledSystemUIMode(
      hideSystemBars ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }
}
