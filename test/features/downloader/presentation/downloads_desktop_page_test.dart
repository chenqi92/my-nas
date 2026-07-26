import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/downloader/presentation/pages/downloader_list_page.dart';
import 'package:my_nas/features/downloader/presentation/pages/downloads_desktop_page.dart';

void main() {
  test('桌面聚合台保留完整客户端管理入口', () {
    expect(desktopDownloaderClientManagerPage(), isA<DownloaderListPage>());
  });
}
