import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/reading/presentation/pages/reading_desktop_page.dart';

void main() {
  group('desktopReadingUsesOnlineBookShelf', () {
    test('只在图书分页且开启在线模式时显示在线书架', () {
      expect(
        desktopReadingUsesOnlineBookShelf(tab: '图书', onlineMode: true),
        isTrue,
      );
      expect(
        desktopReadingUsesOnlineBookShelf(tab: '图书', onlineMode: false),
        isFalse,
      );
      expect(
        desktopReadingUsesOnlineBookShelf(tab: '全部', onlineMode: true),
        isFalse,
      );
      expect(
        desktopReadingUsesOnlineBookShelf(tab: '漫画', onlineMode: true),
        isFalse,
      );
    });
  });
}
