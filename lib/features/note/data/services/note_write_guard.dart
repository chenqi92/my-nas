/// Returns whether a note changed remotely after it was opened locally.
///
/// NAS implementations often expose modification times with one-second
/// precision, so changes within [clockTolerance] are treated as the same
/// revision to avoid false conflicts immediately after a save.
bool hasNoteWriteConflict({
  required DateTime? openedRevision,
  required DateTime? remoteRevision,
  Duration clockTolerance = const Duration(seconds: 1),
}) {
  if (openedRevision == null || remoteRevision == null) return false;
  return remoteRevision.isAfter(openedRevision.add(clockTolerance));
}
