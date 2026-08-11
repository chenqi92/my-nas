import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/pages/video_list_desktop_page.dart';
import 'package:my_nas/features/video/presentation/pages/video_list_page.dart';
import 'package:my_nas/l10n/app_localizations.dart';

class _TestSourcesNotifier extends StateNotifier<AsyncValue<List<SourceEntity>>>
    implements SourcesNotifier {
  _TestSourcesNotifier() : super(const AsyncValue.data([]));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestVideoListNotifier extends StateNotifier<VideoListState>
    implements VideoListNotifier {
  _TestVideoListNotifier(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  void setSearchQuery(String query) {
    final current = state as VideoListLoaded;
    state = current.copyWith(searchQuery: query, searchResults: current.movies);
  }
}

void main() {
  testWidgets('桌面搜索框跨响应式布局切换保留输入和防抖回调', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final metadata = VideoMetadata(
      filePath: '/video/search-target.mkv',
      sourceId: 'nas-1',
      fileName: 'search-target.mkv',
      title: '搜索目标',
    );
    final notifier = _TestVideoListNotifier(
      VideoListLoaded(totalCount: 1, movies: [metadata]),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          videoListProvider.overrideWith((_) => notifier),
          sourcesProvider.overrideWith((_) => _TestSourcesNotifier()),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: VideoListDesktopPage()),
        ),
      ),
    );
    await tester.pump();

    final search = find.byType(TextField);
    expect(search, findsOneWidget);
    await tester.enterText(search, '待保留');

    tester.view.physicalSize = const Size(1100, 900);
    await tester.pump();

    expect(find.text('待保留'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 350));
    expect((notifier.state as VideoListLoaded).searchQuery, '待保留');
    expect(tester.takeException(), isNull);
  });
}
