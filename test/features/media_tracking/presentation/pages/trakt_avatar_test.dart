import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/media_tracking/presentation/pages/trakt_connection_page.dart';

void main() {
  testWidgets('falls back to the local icon when the avatar cannot load', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TraktAvatar(
            avatarUrl: 'https://example.invalid/avatar.png',
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
  });
}
