import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:my_nas/app/router/app_router.dart';
import 'package:my_nas/app/router/routes.dart';
import 'package:my_nas/core/storage/secure_storage_options.dart';
import 'package:my_nas/features/downloader/presentation/pages/downloader_list_page.dart';
import 'package:my_nas/features/file_browser/presentation/pages/file_browser_page.dart';
import 'package:my_nas/features/mine/presentation/pages/mine_page.dart';
import 'package:my_nas/features/music/presentation/pages/music_list_page.dart';
import 'package:my_nas/features/photo/presentation/pages/photo_list_page.dart';
import 'package:my_nas/features/reading/presentation/pages/reading_page.dart';
import 'package:my_nas/features/sources/presentation/pages/sources_page.dart';
import 'package:my_nas/features/transfer/presentation/pages/transfer_manager_page.dart';
import 'package:my_nas/features/video/presentation/pages/video_list_page.dart';
import 'package:my_nas/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('application reaches its first Flutter frame', (tester) async {
    final previousErrorWidgetBuilder = ErrorWidget.builder;
    final previousFlutterErrorHandler = FlutterError.onError;
    final previousPlatformErrorHandler = PlatformDispatcher.instance.onError;

    try {
      await app.main(const []);
      await tester.pump(const Duration(seconds: 3));

      expect(find.byType(MaterialApp), findsOneWidget);
      expect(tester.takeException(), isNull);

      const secureStorageTestKey =
          'com.kkape.mynas.integration_test.secure_storage';
      const secureStorageTestValue = 'verified';
      await defaultSecureStorage.delete(key: secureStorageTestKey);
      addTearDown(() => defaultSecureStorage.delete(key: secureStorageTestKey));
      await writeSecureValueVerified(
        defaultSecureStorage,
        key: secureStorageTestKey,
        value: secureStorageTestValue,
      );
      expect(
        await defaultSecureStorage.read(key: secureStorageTestKey),
        secureStorageTestValue,
      );
      await defaultSecureStorage.delete(key: secureStorageTestKey);

      // iOS 玻璃风格使用原生 UITabBar，Flutter 测试树无法直接点击它。
      // 通过同一 GoRouter 分支逐一进入移动端主页面与工具入口，验证每个
      // 页面可在真机完成构建且未抛出框架异常。测试只读现有数据。
      final routeChecks = <(String, Finder)>[
        (Routes.video, find.byType(VideoListPage)),
        (Routes.music, find.byType(MusicListPage)),
        (Routes.photo, find.byType(PhotoListPage)),
        (Routes.reading, find.byType(ReadingPage)),
        (Routes.mine, find.byType(MinePage)),
        (Routes.sources, find.byType(SourcesPage)),
        (Routes.download, find.byType(DownloaderListPage)),
        (Routes.transfer, find.byType(TransferManagerPage)),
        (Routes.files, find.byType(FileBrowserPage)),
      ];

      for (final (route, finder) in routeChecks) {
        appRouter.go(route);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(finder, findsOneWidget, reason: 'Failed to open $route');
        expect(tester.takeException(), isNull, reason: 'Exception on $route');
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      FlutterError.onError = previousFlutterErrorHandler;
      PlatformDispatcher.instance.onError = previousPlatformErrorHandler;
      ErrorWidget.builder = previousErrorWidgetBuilder;
    }
  });
}
