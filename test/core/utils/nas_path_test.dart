import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/core/utils/nas_path.dart';

void main() {
  group('isWindowsStylePath', () {
    test('识别盘符路径', () {
      expect(isWindowsStylePath(r'C:\Users\demo'), isTrue);
      expect(isWindowsStylePath('C:/Users/demo'), isTrue);
      expect(isWindowsStylePath(r'd:\music'), isTrue);
    });

    test('识别 UNC 路径', () {
      expect(isWindowsStylePath(r'\\server\share\music'), isTrue);
    });

    test('远端 POSIX 路径不算 Windows 风格', () {
      expect(isWindowsStylePath('/music/album'), isFalse);
      expect(isWindowsStylePath('/'), isFalse);
      expect(isWindowsStylePath('music/album'), isFalse);
      // 卷名不带分隔符时不构成 Windows 路径前缀
      expect(isWindowsStylePath('C:music'), isFalse);
    });
  });

  group('nasPathJoin', () {
    test('远端路径始终用 / 拼接（宿主平台无关）', () {
      expect(nasPathJoin('/music/album', 'folder.jpg'), '/music/album/folder.jpg');
      expect(nasPathJoin('/music/album/', 'folder.jpg'), '/music/album/folder.jpg');
      expect(nasPathJoin('/', 'folder.jpg'), '/folder.jpg');
    });

    test('Windows 本地路径用 \\ 拼接', () {
      expect(nasPathJoin(r'C:\music', 'folder.jpg'), r'C:\music\folder.jpg');
      expect(nasPathJoin(r'\\nas\share', 'folder.jpg'), r'\\nas\share\folder.jpg');
    });
  });

  group('nasPathDirname / nasPathBasename', () {
    test('远端路径', () {
      expect(nasPathDirname('/music/album/song.flac'), '/music/album');
      expect(nasPathBasename('/music/album/song.flac'), 'song.flac');
      expect(nasPathBasenameWithoutExtension('/music/album/song.flac'), 'song');
      expect(nasPathExtension('/music/album/song.flac'), '.flac');
    });

    test('Windows 本地路径', () {
      expect(nasPathDirname(r'C:\music\album\song.flac'), r'C:\music\album');
      expect(nasPathBasename(r'C:\music\album\song.flac'), 'song.flac');
      expect(nasPathBasenameWithoutExtension(r'C:\music\album\song.flac'), 'song');
      expect(nasPathExtension(r'C:\music\album\song.flac'), '.flac');
    });

    test('远端路径的 basename 不被反斜杠切断', () {
      // POSIX 上 \ 是合法文件名字符，不应被当作分隔符
      expect(nasPathBasename(r'/music/we\ird.flac'), r'we\ird.flac');
    });
  });
}
