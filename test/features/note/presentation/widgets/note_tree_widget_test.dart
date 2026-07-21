import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/note/presentation/widgets/note_tree_widget.dart';
import 'package:my_nas/l10n/app_localizations.dart';

Widget _host({required TextDirection direction}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Directionality(
    textDirection: direction,
    child: Scaffold(
      body: NoteTreeWidget(
        nodes: [
          NoteTreeNode(
            name: 'Docs',
            path: '/Docs',
            type: NoteTreeNodeType.folder,
            sourceId: 'source',
          ),
          NoteTreeNode(
            name: 'Readme.md',
            path: '/Readme.md',
            type: NoteTreeNodeType.file,
            sourceId: 'source',
          ),
        ],
        selectedPath: '/Readme.md',
        onNodeSelected: (_) {},
        onFolderToggle: (_) {},
        onFolderLoad: (_) {},
        isDark: false,
      ),
    ),
  ),
);

void main() {
  for (final direction in TextDirection.values) {
    testWidgets('exposes accessible nodes in ${direction.name}', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(_host(direction: direction));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel(RegExp('Folder Docs')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Note Readme')), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}
