import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/sources_desktop_page.dart';

void main() {
  group('desktop source connection projection', () {
    test(
      'uses the dedicated media-server status for Jellyfin Emby and Plex',
      () {
        for (final type in [
          SourceType.jellyfin,
          SourceType.emby,
          SourceType.plex,
        ]) {
          expect(
            desktopSourceStatus(
              type,
              standardStatus: SourceStatus.error,
              mediaServerStatus: SourceStatus.connected,
            ),
            SourceStatus.connected,
          );
          expect(
            desktopSourceError(
              type,
              standardError: 'wrong adapter',
              mediaServerError: null,
            ),
            isNull,
          );
        }
      },
    );

    test(
      'keeps ordinary and service sources on the standard connection map',
      () {
        for (final type in [
          SourceType.synology,
          SourceType.smb,
          SourceType.qbittorrent,
          SourceType.nastool,
        ]) {
          expect(
            desktopSourceStatus(
              type,
              standardStatus: SourceStatus.requires2FA,
              mediaServerStatus: SourceStatus.connected,
            ),
            SourceStatus.requires2FA,
          );
          expect(
            desktopSourceError(
              type,
              standardError: 'standard error',
              mediaServerError: 'media error',
            ),
            'standard error',
          );
        }
      },
    );
  });
}
