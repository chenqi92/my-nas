import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/sources/data/services/network_discovery_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/dialogs/source_wizard_dialog.dart';

class _FakeNetworkDiscoveryNotifier extends NetworkDiscoveryNotifier {
  _FakeNetworkDiscoveryNotifier(NetworkDiscoveryState initialState) {
    state = initialState;
  }

  int scanCalls = 0;

  @override
  Future<void> startDiscovery() async {
    scanCalls++;
  }
}

Widget _host(_FakeNetworkDiscoveryNotifier discovery) => ProviderScope(
  overrides: [networkDiscoveryProvider.overrideWith((_) => discovery)],
  child: MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(body: SourceWizardDialog()),
  ),
);

void main() {
  testWidgets('keeps local network discovery visible after an empty scan', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final discovery = _FakeNetworkDiscoveryNotifier(
      NetworkDiscoveryState(lastDiscoveryTime: DateTime(2026)),
    );

    await tester.pumpWidget(_host(discovery));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('source-wizard-discovery')), findsOneWidget);
    expect(find.text('局域网发现'), findsOneWidget);
    expect(find.text('暂未发现可添加的设备，可重新扫描'), findsOneWidget);
    expect(find.text('手动选择'), findsOneWidget);
    expect(discovery.scanCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows discovered devices and manual selection feedback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final discovery = _FakeNetworkDiscoveryNotifier(
      NetworkDiscoveryState(
        devices: const [
          DiscoveredDevice(
            name: 'Living Room NAS',
            host: '192.168.1.10',
            port: 5001,
            type: SourceType.synology,
          ),
        ],
        lastDiscoveryTime: DateTime(2026),
      ),
    );

    await tester.pumpWidget(_host(discovery));
    await tester.pumpAndSettle();

    expect(find.text('Living Room NAS'), findsOneWidget);
    expect(find.text('192.168.1.10:5001 · Synology NAS'), findsOneWidget);

    await tester.tap(find.text('Synology NAS').last);
    await tester.pump();

    expect(find.text('已选择：Synology NAS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exposes S3 as a selectable desktop source type', (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final discovery = _FakeNetworkDiscoveryNotifier(
      NetworkDiscoveryState(lastDiscoveryTime: DateTime(2026)),
    );

    await tester.pumpWidget(_host(discovery));
    await tester.pumpAndSettle();

    expect(find.text('S3 兼容存储'), findsOneWidget);
    await tester.tap(find.text('S3 兼容存储'));
    await tester.pump();

    expect(find.text('已选择：S3 兼容存储'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('starts discovery when the wizard has no prior scan state', (
    tester,
  ) async {
    final discovery = _FakeNetworkDiscoveryNotifier(
      const NetworkDiscoveryState(),
    );

    await tester.pumpWidget(_host(discovery));
    await tester.pump();

    expect(discovery.scanCalls, 1);
  });
}
