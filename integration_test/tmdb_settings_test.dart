import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:integration_test/integration_test.dart';
import 'package:my_nas/features/video/data/services/scraper_manager_service.dart';
import 'package:my_nas/features/video/domain/entities/scraper_source.dart';
import 'package:my_nas/features/video/presentation/pages/scraper_sources_page.dart';
import 'package:my_nas/features/video/presentation/providers/scraper_provider.dart';
import 'package:my_nas/l10n/app_localizations.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'TMDB setup persists through native secure storage and page reload',
    (tester) async {
      // Isolate Hive from the user's data; remove only this test's secure entry.
      final directory = await Directory.systemTemp.createTemp(
        'my_nas_tmdb_test_',
      );
      Hive.init(directory.path);
      final manager = ScraperManagerService();
      await manager.init();
      final source = ScraperSourceEntity(
        name: '',
        type: ScraperType.tmdb,
        isEnabled: false,
      );
      await manager.addSource(source);
      addTearDown(() async {
        await manager.removeCredential(source.id);
        manager.dispose();
        await Hive.close();
        await directory.delete(recursive: true);
      });

      ProviderContainer createContainer() => ProviderContainer(
        overrides: [scraperManagerProvider.overrideWithValue(manager)],
      );

      Future<void> showSettings(ProviderContainer container) async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              locale: Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: ScraperSourcesPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      final toggle = find.descendant(
        of: find.byKey(const ValueKey(ScraperType.tmdb)),
        matching: find.byType(Switch),
      );
      final first = createContainer();
      await showSettings(first);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'tmdb-integration-test-key',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(tester.widget<Switch>(toggle).value, isTrue);
      expect((await manager.getSources()).single.apiKey, isNull);
      expect(
        (await manager.getCredential(source.id))!.apiKey,
        'tmdb-integration-test-key',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      first.dispose();
      final reopened = createContainer();
      addTearDown(reopened.dispose);
      await showSettings(reopened);
      expect(
        reopened.read(scraperSourcesProvider).requireValue.single.isConfigured,
        isTrue,
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(toggle).value, isFalse);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(toggle).value, isTrue);
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
