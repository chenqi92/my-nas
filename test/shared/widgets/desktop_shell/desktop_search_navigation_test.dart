import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/providers/desktop_space_provider.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_scaffold.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_sidebar.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_topbar.dart';

void main() {
  test('global search advertises every implemented desktop content domain', () {
    expect(
      desktopGlobalSearchDomains,
      containsAll(<String>{
        'video',
        'music',
        'photo',
        'reading',
        'files',
        'downloads',
      }),
    );
    expect(
      desktopGlobalSearchMatches('  ARTist ', <String?>['Song', 'The Artist']),
      isTrue,
    );
    expect(desktopGlobalSearchMatches('   ', <String?>['anything']), isFalse);
  });

  test('selected navigation foreground switches with background luminance', () {
    expect(desktopReadableForeground(Colors.white), const Color(0xDE000000));
    expect(desktopReadableForeground(Colors.black), Colors.white);
  });

  testWidgets('sidebar and topbar expose stable control semantics', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Row(
            children: [
              DesktopSidebar(
                space: DesktopSpace.media,
                collapsed: true,
                currentRoute: '/video',
                mediaGroups: const [
                  NavGroup(
                    items: [
                      NavEntry(
                        id: 'films',
                        route: '/video',
                        label: '影视',
                        icon: Icons.movie_outlined,
                        count: '12',
                      ),
                    ],
                  ),
                ],
                opsGroups: const [],
                onSpaceChanged: (_) {},
                onNavigate: (_) {},
                onOpenSettings: () {},
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: DesktopTopbar(
                    crumb: const ['媒体', '影视'],
                    onToggleSidebar: () {},
                    onOpenSearch: () {},
                    onOpenActivity: () {},
                    onOpenAppearance: () {},
                    activityBadge: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('影视, 12'), findsOneWidget);
    expect(find.bySemanticsLabel('媒体'), findsOneWidget);
    expect(find.bySemanticsLabel('控制台'), findsOneWidget);
    expect(find.bySemanticsLabel('折叠侧栏'), findsOneWidget);
    expect(find.bySemanticsLabel('搜索媒体、文件、任务…'), findsOneWidget);
    expect(find.bySemanticsLabel('活动中心'), findsOneWidget);
    expect(find.bySemanticsLabel('外观'), findsOneWidget);
  });
}
