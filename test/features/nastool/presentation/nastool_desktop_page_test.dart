import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/nastool/presentation/pages/nastool_desktop_page.dart';

void main() {
  group('desktopAutomationHasConfiguredService', () {
    test('NAStool 或 MoviePilot 任一已配置即可使用', () {
      expect(
        desktopAutomationHasConfiguredService(
          nastoolCount: 1,
          moviePilotCount: 0,
        ),
        isTrue,
      );
      expect(
        desktopAutomationHasConfiguredService(
          nastoolCount: 0,
          moviePilotCount: 1,
        ),
        isTrue,
      );
      expect(
        desktopAutomationHasConfiguredService(
          nastoolCount: 0,
          moviePilotCount: 0,
        ),
        isFalse,
      );
    });
  });
}
