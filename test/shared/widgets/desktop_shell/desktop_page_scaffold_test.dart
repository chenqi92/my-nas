import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_page_scaffold.dart';

void main() {
  testWidgets('fixed viewport leaves scrolling to the page body', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopPageScaffold(
            title: 'Files',
            scrollable: false,
            body: ListView.builder(
              key: const Key('file-list'),
              itemExtent: 40,
              itemCount: 100,
              itemBuilder: (_, index) => Text('File $index'),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byType(Scrollable), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('file-list')),
      const Offset(0, -500),
    );
    await tester.pump();

    expect(find.text('File 20'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('default mode keeps the shared page scroll view', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopPageScaffold(title: 'Overview', body: Text('Content')),
        ),
      ),
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uncapped mode consumes the available desktop width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopPageScaffold(
            title: 'Films',
            maxWidth: double.infinity,
            body: Text('Content'),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('desktop-page-content'))).width,
      1744,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('desktop-page-body'))).width,
      1744,
    );
    expect(tester.takeException(), isNull);
  });
}
