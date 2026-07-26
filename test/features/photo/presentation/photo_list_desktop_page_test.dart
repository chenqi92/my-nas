import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/photo/data/services/photo_database_service.dart';
import 'package:my_nas/features/photo/presentation/pages/photo_list_desktop_page.dart';
import 'package:my_nas/features/photo/presentation/pages/photo_list_page.dart';

void main() {
  test('桌面照片页保留完整批量管理入口', () {
    expect(desktopPhotoFullManagerPage(), isA<PhotoListPage>());
  });

  test('桌面网格使用带完整动作的查看器数据', () {
    final modified = DateTime(2026, 7, 26);
    final items = desktopPhotoViewerItems([
      PhotoEntity(
        sourceId: 'nas-1',
        filePath: '/photos/a.jpg',
        fileName: 'a.jpg',
        size: 1024,
        modifiedTime: modified,
        thumbnailUrl: 'https://example.test/thumb.jpg',
      ),
    ]);

    expect(items, hasLength(1));
    expect(items.single.name, 'a.jpg');
    expect(items.single.path, '/photos/a.jpg');
    expect(items.single.sourceId, 'nas-1');
    expect(items.single.size, 1024);
    expect(items.single.modifiedAt, modified);
  });
}
