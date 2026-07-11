import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:smb_connect/src/connect/smb_file.dart';
import 'package:smb_connect/src/connect/smb_random_access_file.dart';
import 'package:smb_connect/src/connect/smb_tree.dart';

class _MockSmbTree extends Mock implements SmbTree {}

class _MemoryController extends SmbRandomAccessFileController {
  _MemoryController(SmbFile file, this.bytes)
    : super(file, _MockSmbTree(), FileMode.read);

  final Uint8List bytes;
  int readCalls = 0;

  @override
  Future<int?> open() async => bytes.length;

  @override
  Future<void> close() async {}

  @override
  Future<int> read(Uint8List buff, int offset, int length) async {
    readCalls++;
    final available = bytes.length - offset;
    if (available <= 0) return 0;
    final count = available < length ? available : length;
    buff.setRange(0, count, bytes, offset);
    return count;
  }

  @override
  Future<int> write(
    List<int> buff,
    int position,
    int offset,
    int length,
  ) async => length;
}

SmbFile _fileWithSize(int size) =>
    SmbFile('/video.bin', '/share/video.bin', 'share', 0, 0, 0, 0, size, true);

void main() {
  test('read returns only bytes actually read and reports EOF', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final file = _fileWithSize(bytes.length);
    final randomAccessFile = SmbRandomAccessFile(
      file,
      _MemoryController(file, bytes),
    );

    expect(await randomAccessFile.read(10), bytes);
    expect(await randomAccessFile.read(10), isEmpty);
    expect(await randomAccessFile.readByte(), -1);

    await randomAccessFile.setPosition(bytes.length + 10);
    expect(await randomAccessFile.read(2), isEmpty);
  });

  test(
    'forward seek within the read buffer uses the requested offset',
    () async {
      final bytes = Uint8List.fromList(
        List<int>.generate(16, (index) => index),
      );
      final file = _fileWithSize(bytes.length);
      final controller = _MemoryController(file, bytes);
      final randomAccessFile = SmbRandomAccessFile(file, controller);

      expect(await randomAccessFile.read(2), [0, 1]);
      await randomAccessFile.setPosition(7);
      expect(await randomAccessFile.read(3), [7, 8, 9]);
      expect(controller.readCalls, 1);
    },
  );

  test('negative positions are rejected', () async {
    final file = _fileWithSize(0);
    final controller = _MemoryController(file, Uint8List(0));

    expect(() => SmbRandomAccessFile(file, controller, -1), throwsRangeError);

    final randomAccessFile = SmbRandomAccessFile(file, controller);
    await expectLater(randomAccessFile.setPosition(-1), throwsRangeError);
  });
}
