import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/pages/video_detail_page.dart';
import 'package:my_nas/features/video/presentation/pages/video_list_desktop_page.dart';

void main() {
  test('桌面海报打开完整影视详情页', () {
    final metadata = VideoMetadata(
      filePath: '/video/movie.mkv',
      sourceId: 'nas-1',
      fileName: 'movie.mkv',
    );
    final page = desktopVideoDetailPage(metadata);

    expect(page, isA<VideoDetailPage>());
    expect(page.metadata, same(metadata));
    expect(page.sourceId, 'nas-1');
  });

  test('桌面影视库恢复设置、重复项和完整详情能力', () {
    expect(
      desktopVideoLibraryActions,
      containsAll(<String>[
        'category_settings',
        'library_settings',
        'duplicates',
        'full_detail',
      ]),
    );
  });
}
