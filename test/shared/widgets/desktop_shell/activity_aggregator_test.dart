import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/core/sync/cloud_sync_service.dart';
import 'package:my_nas/shared/widgets/desktop_shell/activity_aggregator.dart';

void main() {
  group('activityItemRoute', () {
    test('transfer items route to /transfer', () {
      expect(activityItemRoute('xfer.123'), '/transfer');
      expect(activityItemRoute('xfer.abc-def'), '/transfer');
    });

    test('video scan routes to /video', () {
      expect(activityItemRoute('video.scan'), '/video');
    });

    test('media scan routes by media type', () {
      expect(activityItemRoute('media.scan.music'), '/music');
      expect(activityItemRoute('media.scan.photo'), '/photo');
      expect(activityItemRoute('media.scan.comic'), '/reading');
      expect(activityItemRoute('media.scan.book'), '/reading');
    });

    test('unknown media scan type has no route', () {
      expect(activityItemRoute('media.scan.unknown'), isNull);
    });

    test('face recognition routes to /photo', () {
      expect(activityItemRoute('face.recognition'), '/photo');
    });

    test('music scrape routes to /music', () {
      expect(activityItemRoute('music.scrape.s1'), '/music');
    });

    test('cloud sync routes to /mine', () {
      expect(activityItemRoute('cloud.sync'), '/mine');
    });

    test('unrecognized id has no route', () {
      expect(activityItemRoute('totally.unknown'), isNull);
      expect(activityItemRoute(''), isNull);
    });
  });

  group('CloudSyncProgress.progress', () {
    test('is 0 when total is 0', () {
      const p = CloudSyncProgress(phase: CloudSyncPhase.preparing);
      expect(p.progress, 0);
    });

    test('is the processed/total ratio', () {
      const p = CloudSyncProgress(
        phase: CloudSyncPhase.syncing,
        processed: 2,
        total: 4,
      );
      expect(p.progress, 0.5);
    });

    test('reaches 1.0 when complete', () {
      const p = CloudSyncProgress(
        phase: CloudSyncPhase.completed,
        processed: 3,
        total: 3,
      );
      expect(p.progress, 1.0);
    });
  });
}
