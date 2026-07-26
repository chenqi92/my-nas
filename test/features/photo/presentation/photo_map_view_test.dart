import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/photo/data/services/photo_database_service.dart';
import 'package:my_nas/features/photo/presentation/pages/photo_map_view.dart';
import 'package:my_nas/l10n/app_localizations.dart';

Widget _host(List<PhotoEntity> photos) => ProviderScope(
  child: MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: PhotoMapView(photos: photos, onOpenPhoto: (_, _) {}),
    ),
  ),
);

void main() {
  testWidgets('shows the completed empty map state without starting a rescan', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _host(const [
        PhotoEntity(
          sourceId: 'nas-1',
          filePath: '/photos/no-gps.jpg',
          fileName: 'no-gps.jpg',
          locationScanned: true,
        ),
      ]),
    );
    await tester.pump();

    expect(find.text('暂未发现带位置的照片'), findsOneWidget);
    expect(find.textContaining('本地读取 JPEG 文件头'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
