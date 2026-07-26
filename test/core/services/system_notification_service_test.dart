import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/core/services/system_notification_service.dart';

void main() {
  test('initializes once and presents every notification', () async {
    var setupCalls = 0;
    final notifications = <(String, String)>[];
    final service = SystemNotificationService(
      isSupported: true,
      setup: () async => setupCalls += 1,
      present: ({required title, required body}) async {
        notifications.add((title, body));
      },
    );

    expect(await service.show(title: 'MyNAS', body: 'A completed'), isTrue);
    expect(await service.show(title: 'MyNAS', body: 'B completed'), isTrue);

    expect(setupCalls, 1);
    expect(notifications, [('MyNAS', 'A completed'), ('MyNAS', 'B completed')]);
  });

  test('does not initialize on unsupported platforms', () async {
    var setupCalls = 0;
    final service = SystemNotificationService(
      isSupported: false,
      setup: () async => setupCalls += 1,
      present: ({required title, required body}) async {},
    );

    expect(await service.show(title: 'MyNAS', body: 'done'), isFalse);
    expect(setupCalls, 0);
  });

  test('returns false when native presentation fails', () async {
    final service = SystemNotificationService(
      isSupported: true,
      setup: () async {},
      present: ({required title, required body}) async {
        throw StateError('native backend unavailable');
      },
    );

    expect(await service.show(title: 'MyNAS', body: 'done'), isFalse);
  });
}
