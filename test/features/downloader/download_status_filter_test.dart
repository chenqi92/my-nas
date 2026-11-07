import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/downloader/presentation/providers/downloader_aggregate_provider.dart';

/// localhost fixture：统一下载状态筛选（含 paused），支撑取消/暂停相关 UI 过滤逻辑。
/// ≠真实 NAS / 不连真实下载后端。
void main() {
  group('DownloadStatusFilter.matches', () {
    test('paused 只匹配 paused', () {
      expect(
        DownloadStatusFilter.paused.matches(UnifiedDownloadStatus.paused),
        isTrue,
      );
      expect(
        DownloadStatusFilter.paused.matches(UnifiedDownloadStatus.downloading),
        isFalse,
      );
      expect(
        DownloadStatusFilter.paused.matches(UnifiedDownloadStatus.completed),
        isFalse,
      );
    });

    test('downloading 包含 waiting', () {
      expect(
        DownloadStatusFilter.downloading.matches(
          UnifiedDownloadStatus.downloading,
        ),
        isTrue,
      );
      expect(
        DownloadStatusFilter.downloading.matches(UnifiedDownloadStatus.waiting),
        isTrue,
      );
      expect(
        DownloadStatusFilter.downloading.matches(UnifiedDownloadStatus.paused),
        isFalse,
      );
    });

    test('all 匹配任意状态', () {
      for (final s in UnifiedDownloadStatus.values) {
        expect(DownloadStatusFilter.all.matches(s), isTrue);
      }
    });

    test('completed / seeding 精确匹配', () {
      expect(
        DownloadStatusFilter.completed.matches(UnifiedDownloadStatus.completed),
        isTrue,
      );
      expect(
        DownloadStatusFilter.seeding.matches(UnifiedDownloadStatus.seeding),
        isTrue,
      );
      expect(
        DownloadStatusFilter.seeding.matches(UnifiedDownloadStatus.downloading),
        isFalse,
      );
    });
  });
}
