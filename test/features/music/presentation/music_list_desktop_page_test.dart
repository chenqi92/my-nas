import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/music/presentation/pages/music_list_desktop_page.dart';
import 'package:my_nas/features/music/presentation/pages/music_list_page.dart';

void main() {
  test('桌面音乐页保留完整分类与搜索管理入口', () {
    expect(desktopMusicFullManagerPage(), isA<MusicListPage>());
  });

  test('桌面单曲菜单覆盖重构前的完整操作', () {
    expect(
      desktopMusicTrackMenuActions,
      containsAll(<String>[
        'play_next',
        'add_to_queue',
        'add_to_playlist',
        'manual_scrape',
        'remove_from_library',
        'delete_from_source',
      ]),
    );
  });
}
