import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/pages/video_detail_page.dart';
import 'package:my_nas/features/video/presentation/pages/video_list_desktop_page.dart';
import 'package:my_nas/l10n/app_localizations.dart';

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  test('桌面海报打开完整影视详情页', () {
    final metadata = VideoMetadata(
      filePath: '/video/movie.mkv',
      sourceId: 'nas-1',
      fileName: 'movie.mkv',
    );
    final page = desktopVideoDetailPage(metadata);

    expect(page, isA<VideoDetailPage>());
    expect(page.metadata, same(metadata));
    expect(page.sourceId, 'nas-1');
  });

  test('桌面影视库恢复设置、重复项和完整详情能力', () {
    expect(
      desktopVideoLibraryActions,
      containsAll(<String>[
        'category_settings',
        'library_settings',
        'duplicates',
        'full_detail',
      ]),
    );
  });

  testWidgets('桌面列表在页面滚动容器中保持海报和内容可见', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final metadata = VideoMetadata(
      filePath: '/video/visible-movie.mkv',
      sourceId: 'nas-1',
      fileName: 'visible-movie.mkv',
      title: '可见的影视条目',
      year: 2026,
      runtime: 96,
    );

    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 1000,
          child: desktopVideoPosterList(
            items: [metadata],
            sourceNames: const {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('可见的影视条目'), findsOneWidget);
    expect(find.textContaining('2026'), findsOneWidget);
    expect(
      tester.getSize(
        find.byKey(ValueKey('desktop-video-list-poster-${metadata.uniqueKey}')),
      ),
      const Size(64, 96),
    );
    expect(tester.takeException(), isNull);
  });
}
