import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/video/data/services/scraper_manager_service.dart';
import 'package:my_nas/features/video/domain/entities/scraper_source.dart';
import 'package:my_nas/features/video/presentation/pages/scraper_sources_page.dart';
import 'package:my_nas/features/video/presentation/providers/scraper_provider.dart';
import 'package:my_nas/l10n/app_localizations.dart';

// Match the storage contract: list metadata and credentials are read separately.
class _ScraperManager extends Fake implements ScraperManagerService {
  final sources = <ScraperSourceEntity>[];
  final credentials = <String, ScraperCredential>{};
  Completer<void>? pendingSave;
  int saveCalls = 0;

  @override
  Future<void> init() async {}

  @override
  Future<void> migrateFromLegacyConfig() async {}

  @override
  Future<List<ScraperSourceEntity>> getSources() async => [...sources];

  @override
  Future<ScraperCredential?> getCredential(String id) async => credentials[id];

  @override
  Future<void> addSource(ScraperSourceEntity source) => updateSource(source);

  @override
  Future<void> updateSource(ScraperSourceEntity source) async {
    saveCalls++;
    await pendingSave?.future;
    credentials[source.id] = ScraperCredential(
      apiKey: source.apiKey,
      cookie: source.cookie,
    );
    sources
      ..removeWhere((s) => s.id == source.id)
      ..add(
        ScraperSourceEntity.fromJson(
          source.toJson()
            ..remove('apiKey')
            ..remove('cookie'),
        ),
      );
  }

  @override
  Future<void> toggleSource(String id, {required bool enabled}) async {
    final index = sources.indexWhere((s) => s.id == id);
    sources[index] = sources[index].copyWith(isEnabled: enabled);
  }
}

Finder _card(ScraperType type) => find.byKey(ValueKey(type));

Finder _switch(ScraperType type) =>
    find.descendant(of: _card(type), matching: find.byType(Switch));

Future<ProviderContainer> _mount(
  WidgetTester tester,
  _ScraperManager manager,
) async {
  tester.view.physicalSize = const Size(1100, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [scraperManagerProvider.overrideWithValue(manager)],
  );
  addTearDown(container.dispose);
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
  return container;
}

Future<void> _saveKey(WidgetTester tester, String key) async {
  await tester.enterText(find.byType(TextField).first, key);
  await tester.tap(find.widgetWithText(FilledButton, '保存'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'saved TMDB credentials survive reload and off/on without prompting',
    (tester) async {
      final manager = _ScraperManager();
      final container = await _mount(tester, manager);
      await tester.tap(_switch(ScraperType.tmdb));
      await tester.pumpAndSettle();
      await _saveKey(tester, '  test-api-key  ');

      expect(find.byType(Dialog), findsNothing);
      expect(tester.widget<Switch>(_switch(ScraperType.tmdb)).value, isTrue);
      expect(manager.sources.single.apiKey, isNull);
      expect(
        container.read(scraperSourcesProvider).requireValue.single.isConfigured,
        isTrue,
      );

      container.invalidate(scraperSourcesProvider);
      await tester.pumpAndSettle();
      await tester.tap(_switch(ScraperType.tmdb));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(_switch(ScraperType.tmdb)).value, isFalse);
      await tester.tap(_switch(ScraperType.tmdb));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(tester.widget<Switch>(_switch(ScraperType.tmdb)).value, isTrue);

      await tester.tap(
        find.descendant(
          of: _card(ScraperType.tmdb),
          matching: find.byIcon(Icons.settings_outlined),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'test-api-key',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'enabling an existing unconfigured source enables it after save',
    (tester) async {
      final manager = _ScraperManager()
        ..sources.add(
          ScraperSourceEntity(
            id: 'tmdb',
            name: '',
            type: ScraperType.tmdb,
            isEnabled: false,
          ),
        );
      await _mount(tester, manager);
      await tester.tap(_switch(ScraperType.tmdb));
      await tester.pumpAndSettle();
      await _saveKey(tester, 'test-api-key');
      expect(manager.sources.single.isEnabled, isTrue);
      expect(tester.widget<Switch>(_switch(ScraperType.tmdb)).value, isTrue);
      expect(find.byType(Dialog), findsNothing);
    },
  );

  testWidgets('editing a disabled source preserves its disabled state', (
    tester,
  ) async {
    final manager = _ScraperManager()
      ..sources.add(
        ScraperSourceEntity(
          id: 'tmdb',
          name: '',
          type: ScraperType.tmdb,
          isEnabled: false,
        ),
      )
      ..credentials['tmdb'] = const ScraperCredential(apiKey: 'old-key');
    await _mount(tester, manager);
    await tester.tap(
      find.descendant(
        of: _card(ScraperType.tmdb),
        matching: find.byIcon(Icons.settings_outlined),
      ),
    );
    await tester.pumpAndSettle();
    await _saveKey(tester, 'new-key');
    expect(manager.sources.single.isEnabled, isFalse);
    expect(manager.credentials['tmdb']!.apiKey, 'new-key');
    expect(tester.widget<Switch>(_switch(ScraperType.tmdb)).value, isFalse);
  });

  testWidgets('saved cookies also restore configured state', (tester) async {
    final manager = _ScraperManager()
      ..sources.add(
        ScraperSourceEntity(
          id: 'douban',
          name: '',
          type: ScraperType.doubanWeb,
          isEnabled: false,
        ),
      )
      ..credentials['douban'] = const ScraperCredential(cookie: 'test-cookie');
    final container = await _mount(tester, manager);
    expect(
      container.read(scraperSourcesProvider).requireValue.single.isConfigured,
      isTrue,
    );
    await tester.tap(_switch(ScraperType.doubanWeb));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(tester.widget<Switch>(_switch(ScraperType.doubanWeb)).value, isTrue);
  });

  testWidgets(
    'failed save keeps input and allows retry without duplicate saves',
    (tester) async {
      final pending = Completer<void>();
      final manager = _ScraperManager()..pendingSave = pending;
      await _mount(tester, manager);
      await tester.tap(_switch(ScraperType.tmdb));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'test-api-key');
      final save = find.widgetWithText(FilledButton, '保存');
      await tester.tap(save);
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.tap(save);
      expect(manager.saveCalls, 1);

      pending.completeError(Exception('test storage unavailable'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      final l = AppLocalizations.of(tester.element(find.byType(Dialog)));
      expect(find.text(l.errorUnknown), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'test-api-key',
      );
      expect(manager.sources, isEmpty);
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

      manager.pendingSave = null;
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(manager.sources, hasLength(1));
      expect(tester.widget<Switch>(_switch(ScraperType.tmdb)).value, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelling initial setup leaves TMDB disabled', (tester) async {
    final manager = _ScraperManager();
    await _mount(tester, manager);
    await tester.tap(_switch(ScraperType.tmdb));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(TextField).first)).pop();
    await tester.pumpAndSettle();
    expect(manager.sources, isEmpty);
    expect(tester.widget<Switch>(_switch(ScraperType.tmdb)).value, isFalse);
  });
}
