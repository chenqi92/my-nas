import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/note/data/services/note_write_guard.dart';

void main() {
  group('hasNoteWriteConflict', () {
    final opened = DateTime.utc(2026, 7, 11, 8);

    test('does not report a conflict when either revision is unknown', () {
      expect(
        hasNoteWriteConflict(openedRevision: null, remoteRevision: opened),
        isFalse,
      );
      expect(
        hasNoteWriteConflict(openedRevision: opened, remoteRevision: null),
        isFalse,
      );
    });

    test('allows timestamp precision drift within one second', () {
      expect(
        hasNoteWriteConflict(
          openedRevision: opened,
          remoteRevision: opened.add(const Duration(seconds: 1)),
        ),
        isFalse,
      );
    });

    test('reports a newer remote revision', () {
      expect(
        hasNoteWriteConflict(
          openedRevision: opened,
          remoteRevision: opened.add(const Duration(seconds: 2)),
        ),
        isTrue,
      );
    });
  });
}
