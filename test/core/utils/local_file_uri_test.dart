import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/core/utils/local_file_uri.dart';

void main() {
  group('local file URI', () {
    test('POSIX 路径可往返并编码空格和中文', () {
      const path = '/tmp/海报 a.jpg';
      final uri = localPathToFileUri(path);

      expect(uri, 'file:///tmp/%E6%B5%B7%E6%8A%A5%20a.jpg');
      expect(localPathFromFileUri(uri), path);
    });

    test('Windows 盘符路径在任意宿主平台都生成规范 URI', () {
      const path = r'C:\Users\name\海报 a.jpg';
      final uri = localPathToFileUri(path);

      expect(uri, 'file:///C:/Users/name/%E6%B5%B7%E6%8A%A5%20a.jpg');
      expect(localPathFromFileUri(uri), path);
    });

    test('兼容旧版 file 双斜杠加 Windows 盘符格式', () {
      expect(
        localPathFromFileUri(r'file://C:\Users\name\cover.jpg'),
        r'C:\Users\name\cover.jpg',
      );
    });

    test('UNC 路径可往返', () {
      const path = r'\\nas\share\海报.jpg';
      final uri = localPathToFileUri(path);

      expect(uri, startsWith('file://nas/share/'));
      expect(localPathFromFileUri(uri), path);
    });

    test('非 file URL 返回 null', () {
      expect(localPathFromFileUri('https://example.com/a.jpg'), isNull);
    });
  });
}
