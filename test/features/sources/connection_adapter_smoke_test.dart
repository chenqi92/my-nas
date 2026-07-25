import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/music/data/services/music_database_service.dart';
import 'package:my_nas/features/music/presentation/pages/music_list_page.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/domain/entities/source_form_config.dart';
import 'package:my_nas/features/sources/presentation/pages/source_form_page.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/data/services/video_scanner_service.dart';
import 'package:my_nas/media_server_adapters/emby/emby_adapter.dart';
import 'package:my_nas/media_server_adapters/jellyfin/jellyfin_adapter.dart';
import 'package:my_nas/media_server_adapters/plex/plex_adapter.dart';
import 'package:my_nas/nas_adapters/fnos/fnos_adapter.dart';
import 'package:my_nas/nas_adapters/ftp/ftp_adapter.dart';
import 'package:my_nas/nas_adapters/qnap/qnap_adapter.dart';
import 'package:my_nas/nas_adapters/sftp/sftp_adapter.dart';
import 'package:my_nas/nas_adapters/smb/smb_adapter.dart';
import 'package:my_nas/nas_adapters/ugreen/ugreen_adapter.dart';
import 'package:my_nas/nas_adapters/upnp/upnp_adapter.dart';
import 'package:my_nas/nas_adapters/webdav/webdav_adapter.dart';
import 'package:my_nas/service_adapters/base/service_adapter.dart';

void main() {
  test('connection adapters compile as one integration surface', () {
    expect(<Type>[
      FnOSAdapter,
      FtpAdapter,
      QnapAdapter,
      SftpAdapter,
      SmbAdapter,
      UGreenAdapter,
      UpnpAdapter,
      WebDavAdapter,
      EmbyAdapter,
      JellyfinAdapter,
      PlexAdapter,
    ], hasLength(11));
    expect(<Type>[
      SourceFormConfig,
      SourceFormPage,
      MusicDatabaseService,
      MusicListNotifier,
      VideoDatabaseService,
      VideoScannerService,
    ], hasLength(6));
  });

  test('credential updates preserve unrelated secure fields', () {
    const existing = SourceCredential(
      password: 'old-password',
      deviceId: 'device-id',
      accessToken: 'access-token',
      extraSecrets: {'privateKey': 'pem'},
    );

    final merged = existing.merge(
      const SourceCredential(password: 'new-password'),
    );

    expect(merged.password, 'new-password');
    expect(merged.deviceId, 'device-id');
    expect(merged.accessToken, 'access-token');
    expect(merged.extraSecrets, {'privateKey': 'pem'});
  });

  test('media servers use service adapters instead of NAS adapters', () {
    expect(SourceType.emby.isServiceSource, isTrue);
    expect(SourceType.jellyfin.isServiceSource, isTrue);
    expect(SourceType.plex.isServiceSource, isTrue);
    expect(SourceType.smb.isServiceSource, isFalse);
    expect(SourceType.webdav.isServiceSource, isFalse);
  });

  test('runtime authentication can be merged into a connection config', () {
    const original = ServiceConnectionConfig(
      baseUrl: 'http://media.local',
      username: 'tester',
      password: 'secret',
      extraConfig: {'sourceId': 'source-1'},
    );

    final authenticated = original.copyWith(
      extraConfig: {
        ...?original.extraConfig,
        'accessToken': 'runtime-token',
        'userId': 'user-1',
      },
    );

    expect(authenticated.baseUrl, original.baseUrl);
    expect(authenticated.username, original.username);
    expect(authenticated.password, original.password);
    expect(authenticated.extraConfig, {
      'sourceId': 'source-1',
      'accessToken': 'runtime-token',
      'userId': 'user-1',
    });
    expect(original.extraConfig, {'sourceId': 'source-1'});
  });
}
