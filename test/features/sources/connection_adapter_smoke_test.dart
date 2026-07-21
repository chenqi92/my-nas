import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/music/data/services/music_database_service.dart';
import 'package:my_nas/features/music/presentation/pages/music_list_page.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
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
}
