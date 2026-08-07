import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/core/utils/file_name_sanitizer.dart';

void main() {
  group('非法字符', () {
    test('Windows 禁止字符替换为下划线', () {
      expect(sanitizeFileName('a:b*c?d"e<f>g|h.txt'), 'a_b_c_d_e_f_g_h.txt');
    });

    test('路径分隔符被当作非法字符（不保留路径语义）', () {
      expect(sanitizeFileName('dir/sub/file.txt'), 'dir_sub_file.txt');
      expect(sanitizeFileName(r'dir\sub\file.txt'), 'dir_sub_file.txt');
    });

    test('控制字符被替换', () {
      final soh = String.fromCharCode(0x01);
      final stx = String.fromCharCode(0x02);
      final del = String.fromCharCode(0x7F);
      expect(sanitizeFileName('a${soh}b${stx}c.txt'), 'a_b_c.txt');
      expect(sanitizeFileName('tab\there.txt'), 'tab_here.txt');
      expect(sanitizeFileName('del${del}name.txt'), 'del_name.txt');
    });

    test('自定义替换字符', () {
      expect(sanitizeFileName('a:b.txt', replacement: '-'), 'a-b.txt');
    });

    test('合法名字原样返回', () {
      expect(sanitizeFileName('正常文件名 - 第01集.mkv'), '正常文件名 - 第01集.mkv');
    });
  });

  group('尾部点和空格', () {
    test('剥除尾部点', () {
      expect(sanitizeFileName('file.txt.'), 'file.txt');
      expect(sanitizeFileName('file...'), 'file');
    });

    test('剥除尾部空格与首尾空白', () {
      expect(sanitizeFileName('  file.txt  '), 'file.txt');
      expect(sanitizeFileName('file.txt . . '), 'file.txt');
    });
  });

  group('Windows 保留名', () {
    test('裸保留名加前缀', () {
      expect(sanitizeFileName('CON'), '_CON');
      expect(sanitizeFileName('NUL'), '_NUL');
      expect(sanitizeFileName('COM1'), '_COM1');
      expect(sanitizeFileName('LPT9'), '_LPT9');
    });

    test('带扩展名的保留名同样加前缀', () {
      expect(sanitizeFileName('CON.txt'), '_CON.txt');
    });

    test('大小写不敏感', () {
      expect(sanitizeFileName('con.txt'), '_con.txt');
      expect(sanitizeFileName('Nul'), '_Nul');
    });

    test('保留名作为前缀的正常文件不受影响', () {
      expect(sanitizeFileName('CONTENT.txt'), 'CONTENT.txt');
      expect(sanitizeFileName('COM10'), 'COM10');
    });
  });

  group('长度截断', () {
    test('ASCII 超长截断并保留扩展名', () {
      final result = sanitizeFileName('${'a' * 300}.mkv');
      expect(utf8.encode(result).length, lessThanOrEqualTo(200));
      expect(result.endsWith('.mkv'), isTrue);
    });

    test('多字节字符不被切裂', () {
      final result = sanitizeFileName('中' * 300);
      expect(utf8.encode(result).length, lessThanOrEqualTo(200));
      // 往返编解码一致即说明没有产生半个字符
      expect(utf8.decode(utf8.encode(result)), result);
      expect(result.contains('�'), isFalse);
    });

    test('自定义字节上限', () {
      final result = sanitizeFileName('${'a' * 100}.txt', maxBytes: 20);
      expect(utf8.encode(result).length, lessThanOrEqualTo(20));
      expect(result.endsWith('.txt'), isTrue);
    });

    test('未超限时不截断', () {
      expect(sanitizeFileName('short.txt'), 'short.txt');
    });

    test('超长扩展名不被当作扩展名保留', () {
      final result = sanitizeFileName('a.${'x' * 400}', maxBytes: 50);
      expect(utf8.encode(result).length, lessThanOrEqualTo(50));
    });
  });

  group('空值回退', () {
    test('空字符串回退', () {
      expect(sanitizeFileName(''), 'unnamed');
    });

    test('全非法字符清洗后非空（替换字符保留）', () {
      expect(sanitizeFileName('///'), '___');
    });

    test('全为点和空格回退', () {
      expect(sanitizeFileName('  ...  '), 'unnamed');
    });

    test('自定义回退值', () {
      expect(sanitizeFileName('', fallback: 'x.bin'), 'x.bin');
    });
  });
}
