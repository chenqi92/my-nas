import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:my_nas/core/constants/app_constants.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';

typedef NotificationSetup = Future<void> Function();
typedef NotificationPresenter =
    Future<void> Function({required String title, required String body});

/// Sends native desktop notifications with a graceful in-app fallback.
///
/// The caller should still show its normal toast. This service returns `false`
/// when the current platform is unsupported or the native notification backend
/// cannot be initialized, so a missing OS integration never hides completion
/// feedback from the user.
class SystemNotificationService {
  SystemNotificationService({
    NotificationSetup? setup,
    NotificationPresenter? present,
    bool? isSupported,
  }) : _setup = setup ?? _defaultSetup,
       _present = present ?? _defaultPresent,
       _isSupported = isSupported ?? _desktopPlatformSupported;

  static final instance = SystemNotificationService();

  final NotificationSetup _setup;
  final NotificationPresenter _present;
  final bool _isSupported;

  bool _initialized = false;

  Future<bool> show({required String title, required String body}) async {
    if (!_isSupported) return false;
    try {
      if (!_initialized) {
        await _setup();
        _initialized = true;
      }
      await _present(title: title, body: body);
      return true;
    } on Object catch (error, stackTrace) {
      AppError.ignore(error, stackTrace, '桌面系统通知不可用，保留应用内提示');
      return false;
    }
  }

  static bool get _desktopPlatformSupported =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  static Future<void> _defaultSetup() => localNotifier.setup(
    appName: AppConstants.appName,
    shortcutPolicy: ShortcutPolicy.requireCreate,
  );

  static Future<void> _defaultPresent({
    required String title,
    required String body,
  }) => LocalNotification(title: title, body: body).show();
}
