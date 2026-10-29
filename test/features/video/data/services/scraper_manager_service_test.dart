import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:my_nas/features/video/data/services/scraper_manager_service.dart';
import 'package:my_nas/features/video/domain/entities/scraper_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final manager = ScraperManagerService();
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('my_nas_scraper_test_');
    Hive.init(directory.path);
    await manager.init();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'write') {
            throw PlatformException(code: 'test_write_failed');
          }
          return null;
        });
  });

  setUp(() async => Hive.box<dynamic>('scrapers').clear());

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    manager.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'failed credential write does not create a partially configured source',
    () async {
      final source = ScraperSourceEntity(
        name: '',
        type: ScraperType.tmdb,
        apiKey: 'test-key',
      );
      await expectLater(
        manager.addSource(source),
        throwsA(isA<PlatformException>()),
      );
      expect(await manager.getSources(), isEmpty);
    },
  );

  test(
    'failed credential update does not enable an unconfigured source',
    () async {
      final source = ScraperSourceEntity(
        name: '',
        type: ScraperType.tmdb,
        isEnabled: false,
      );
      await manager.addSource(source);
      await expectLater(
        manager.updateSource(
          source.copyWith(isEnabled: true, apiKey: 'test-key'),
        ),
        throwsA(isA<PlatformException>()),
      );
      final persisted = (await manager.getSources()).single;
      expect(persisted.isEnabled, isFalse);
      expect(persisted.apiKey, isNull);
    },
  );
}
