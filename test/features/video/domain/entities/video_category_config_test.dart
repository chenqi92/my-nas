import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/video/domain/entities/video_category_config.dart';

void main() {
  group('VideoCategorySettings.visibleSectionsForLibrary', () {
    test('shows other videos when they are the only library content', () {
      final settings = VideoCategorySettings.defaults();

      final visible = settings.visibleSectionsForLibrary(
        movieCount: 0,
        tvShowCount: 0,
        otherCount: 1,
      );

      expect(
        visible.any((section) => section.category == VideoHomeCategory.others),
        isTrue,
      );
    });

    test('preserves the hidden preference when recognized videos exist', () {
      final settings = VideoCategorySettings.defaults();

      final visible = settings.visibleSectionsForLibrary(
        movieCount: 1,
        tvShowCount: 0,
        otherCount: 1,
      );

      expect(
        visible.any((section) => section.category == VideoHomeCategory.others),
        isFalse,
      );
    });

    test('does not duplicate an already visible other section', () {
      final settings = VideoCategorySettings(
        sections: [
          VideoCategorySectionConfig(
            category: VideoHomeCategory.others,
            order: 0,
          ),
        ],
      );

      final visible = settings.visibleSectionsForLibrary(
        movieCount: 0,
        tvShowCount: 0,
        otherCount: 1,
      );

      expect(
        visible.where(
          (section) => section.category == VideoHomeCategory.others,
        ),
        hasLength(1),
      );
    });
  });
}
